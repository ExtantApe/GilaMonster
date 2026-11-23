#!/usr/bin/env swift
// Builds the GilaMonster brand kit from one master file: a pixel-art mark in `mark.txt` (D276).
//   swift scripts/brand-kit.swift brand/kit
// Writes into <folder>/out: the mark as SVG, circle and square profile marks, the app icon at every size (.icns,
// .ico, 1024 and 32), and the menu-bar template at 1x and 2x. The banners, README headers and release images
// wait for the name's wordmark and tagline (`wordmarkReady`).
// Every text and outline pair is checked against WCAG first (D149), in typical color vision and with protanopia,
// deuteranopia, tritanopia and achromatopsia simulated: large text 3:1, small text 4.5:1, outlines 3:1. If any
// pair fails, nothing is written and the script exits 1.
import AppKit

// MARK: The master

struct Mark {
    var size: Int
    var cells: [[UInt32?]]
    var palette: [Character: UInt32]
}

func readMark(_ url: URL) -> Mark {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { fail("Can't read \(url.path).") }
    var palette: [Character: UInt32] = [:]
    var rows: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("#") || line.isEmpty { continue }
        if line.hasPrefix("palette ") {
            let parts = line.split(separator: " ")
            guard parts.count >= 3, parts[1].count == 1, let hex = UInt32(parts[2].dropFirst(), radix: 16) else { fail("Bad palette line: \(line)") }
            palette[parts[1].first!] = hex
        } else {
            rows.append(String(line))
        }
    }
    guard !rows.isEmpty, rows.allSatisfy({ $0.count == rows.count }) else { fail("The mark must be square: every row as long as there are rows.") }
    let cells = rows.map { row in row.map { c -> UInt32? in
        if c == "." { return nil }
        guard let hex = palette[c] else { fail("\"\(c)\" isn't in the palette.") }
        return hex
    } }
    return Mark(size: rows.count, cells: cells, palette: palette)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("brand-kit: \(message)\n".utf8))
    exit(1)
}

// MARK: Colors and WCAG

// The main palette, chosen 2026-11-23 (D272/D276): basalt, cream, mid grey, and the deep dark background.
let ink: UInt32 = 0x2A282C, cream: UInt32 = 0xF5EBDD, surface: UInt32 = 0xFFFFFF, muted: UInt32 = 0x4B474F
let darkBack: UInt32 = 0x1E1C20, darkInk: UInt32 = 0xF5EBDD, darkMuted: UInt32 = 0xB9B5BE
// The tile is flat cream in every appearance. The mark's outline is basalt, so it only reads on a light tile: there
// is no dark tile, and the profile marks come in one version.
let tileTop: UInt32 = 0xF5EBDD, tileBottom: UInt32 = 0xF5EBDD
/// The banners, README headers and release images need the name's wordmark and tagline, not chosen yet.
let wordmarkReady = false
/// The art red-orange, for the trim along the bottom of banners and release images.
let brandOrange: UInt32 = 0xE4572E

func linear(_ c: UInt32) -> Double { let v = Double(c) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
func luminance(_ h: UInt32) -> Double { 0.2126 * linear(h >> 16 & 0xFF) + 0.7152 * linear(h >> 8 & 0xFF) + 0.0722 * linear(h & 0xFF) }
func contrast(_ a: UInt32, _ b: UInt32) -> Double { let x = luminance(a), y = luminance(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }

struct Pair { let what: String; let fg: UInt32; let bg: UInt32; let minimum: Double }

// Color vision: Machado, Oliveira and Fernandes (2009) at full strength, and achromatopsia as luminance only. The
// same matrices as LeafJuiceCore's Palette.simulate.
enum Vision: String, CaseIterable { case typical, protanopia, deuteranopia, tritanopia, achromatopsia }
let visionMatrices: [Vision: [[Double]]] = [
    .protanopia: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    .deuteranopia: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    .tritanopia: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
]
func simulate(_ hex: UInt32, _ vision: Vision) -> UInt32 {
    if vision == .typical { return hex }
    let c = [linear(hex >> 16 & 0xFF), linear(hex >> 8 & 0xFF), linear(hex & 0xFF)]
    let out: [Double]
    if vision == .achromatopsia { let y = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; out = [y, y, y] }
    else { let m = visionMatrices[vision]!; out = (0..<3).map { i in m[i][0] * c[0] + m[i][1] * c[1] + m[i][2] * c[2] } }
    func encode(_ v: Double) -> UInt32 {
        let x = min(max(v, 0), 1)
        return UInt32(((x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055) * 255).rounded())
    }
    return encode(out[0]) << 16 | encode(out[1]) << 8 | encode(out[2])
}
/// The lowest ratio for a pair across every kind of color vision, and which one it was.
func lowest(_ p: Pair) -> (Double, Vision) {
    Vision.allCases.map { (contrast(simulate(p.fg, $0), simulate(p.bg, $0)), $0) }.min { $0.0 < $1.0 }!
}

func checkPairs(_ pairs: [Pair]) -> [String] {
    pairs.compactMap { p in
        let (r, v) = lowest(p)
        return r < p.minimum ? "\(p.what): \(String(format: "%.2f", r)):1 (\(v.rawValue)), needs \(p.minimum):1" : nil
    }
}

// MARK: Drawing

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func cg(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func canvas(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(true)
    return ctx
}

/// Draws the mark with its top-left at (x, y) in top-down coordinates, each pixel `cell` points wide.
func drawMark(_ m: Mark, in ctx: CGContext, x: CGFloat, y: CGFloat, cell: CGFloat, height: Int) {
    ctx.setShouldAntialias(false)
    for (row, cells) in m.cells.enumerated() {
        for (col, hex) in cells.enumerated() {
            guard let hex else { continue }
            ctx.setFillColor(cg(hex))
            let top = y + CGFloat(row) * cell
            ctx.fill(CGRect(x: (x + CGFloat(col) * cell).rounded(), y: (CGFloat(height) - top - cell).rounded(), width: cell.rounded(), height: cell.rounded()))
        }
    }
    ctx.setShouldAntialias(true)
}

func gradient(_ ctx: CGContext, _ top: UInt32, _ bottom: UInt32, _ rect: CGRect) {
    let g = CGGradient(colorsSpace: sRGB, colors: [cg(top), cg(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
}

/// A profile mark: the mark centred on a disc or a rounded square, with clear space all round.
func profile(_ m: Mark, size: Int, circle: Bool, dark: Bool) -> CGImage {
    let ctx = canvas(size, size)
    let s = CGFloat(size)
    let shape = circle ? CGPath(ellipseIn: CGRect(x: 0, y: 0, width: s, height: s), transform: nil)
                       : CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
    ctx.addPath(shape); ctx.clip()
    gradient(ctx, dark ? darkBack : tileTop, dark ? darkBack : tileBottom, CGRect(x: 0, y: 0, width: s, height: s))
    // A circle needs more clear space than a square for the corners of the art to stay inside.
    let cell = (s * (circle ? 0.62 : 0.72) / CGFloat(m.size)).rounded(.down)
    let art = cell * CGFloat(m.size)
    drawMark(m, in: ctx, x: (s - art) / 2, y: (s - art) / 2, cell: cell, height: size)
    return ctx.makeImage()!
}

/// The macOS app icon: the square mark on a 824-point tile inside a 1024 canvas, as Apple's grid has it.
func appIcon(_ m: Mark, size: Int) -> CGImage {
    let ctx = canvas(size, size)
    let s = CGFloat(size)
    let inset = size <= 64 ? s * 0.04 : s * 0.0977
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)); ctx.clip()
    gradient(ctx, tileTop, tileBottom, tile)
    let cell = max(1, (tile.width * 0.78 / CGFloat(m.size)).rounded(.down))
    let art = cell * CGFloat(m.size)
    drawMark(m, in: ctx, x: (s - art) / 2, y: (s - art) / 2, cell: cell, height: size)
    return ctx.makeImage()!
}

/// At 32 px and under, the tile runs to the edge and each art pixel is a whole number of screen pixels, so the pixel
/// art stays sharp. This is what icon-small.svg describes.
func smallIcon(_ m: Mark, size: Int) -> CGImage {
    let ctx = canvas(size, size)
    let s = CGFloat(size)
    let tile = CGRect(x: 0, y: 0, width: s, height: s)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)); ctx.clip()
    gradient(ctx, tileTop, tileBottom, tile)
    let cell = CGFloat(max(1, size / m.size))
    let art = cell * CGFloat(m.size)
    drawMark(m, in: ctx, x: ((s - art) / 2).rounded(.down), y: ((s - art) / 2).rounded(.down), cell: cell, height: size)
    return ctx.makeImage()!
}

/// The app icon as SVG: the master the PNGs, .icns and .ico are made from. `small` is the 16 to 32 px version.
func iconSVG(_ m: Mark, small: Bool) -> String {
    let side = small ? 32.0 : 1024.0
    let inset = small ? 0.0 : 1024 * 0.0977
    let tile = side - inset * 2
    let radius = small ? side * 0.2 : tile * 0.225
    let cell = small ? Double(32 / m.size) : (tile * 0.78 / Double(m.size)).rounded(.down)
    let origin = ((side - cell * Double(m.size)) / 2).rounded(.down)
    func hex(_ v: UInt32) -> String { "#" + String(format: "%06X", v) }
    var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(side))\" height=\"\(Int(side))\" viewBox=\"0 0 \(Int(side)) \(Int(side))\" shape-rendering=\"crispEdges\" role=\"img\" aria-label=\"GilaMonster\">\n"
    out += "<title>GilaMonster</title>\n<defs><linearGradient id=\"t\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(hex(tileTop))\"/><stop offset=\"1\" stop-color=\"\(hex(tileBottom))\"/></linearGradient></defs>\n"
    out += "<rect x=\"\(inset)\" y=\"\(inset)\" width=\"\(tile)\" height=\"\(tile)\" rx=\"\(radius)\" fill=\"url(#t)\" shape-rendering=\"geometricPrecision\"/>\n"
    for (y, row) in m.cells.enumerated() {
        var x = 0
        while x < row.count {
            guard let v = row[x] else { x += 1; continue }
            var run = 1
            while x + run < row.count, row[x + run] == v { run += 1 }
            out += "<rect x=\"\(origin + Double(x) * cell)\" y=\"\(origin + Double(y) * cell)\" width=\"\(Double(run) * cell)\" height=\"\(cell)\" fill=\"\(hex(v))\"/>\n"
            x += run
        }
    }
    return out + "</svg>\n"
}

func png(_ image: CGImage) -> Data {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fail("Couldn't encode a PNG.") }
    return data
}

/// A Windows .ico holding PNG images, which Windows Vista and later read at every size.
func ico(_ images: [(Int, Data)]) -> Data {
    var out = Data()
    func le16(_ v: Int) { out.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    func le32(_ v: Int) { le16(v & 0xFFFF); le16(v >> 16 & 0xFFFF) }
    le16(0); le16(1); le16(images.count)
    var offset = 6 + 16 * images.count
    for (size, data) in images {
        out.append(UInt8(size >= 256 ? 0 : size)); out.append(UInt8(size >= 256 ? 0 : size))
        out.append(0); out.append(0)
        le16(1); le16(32); le32(data.count); le32(offset)
        offset += data.count
    }
    for (_, data) in images { out.append(data) }
    return out
}

/// Reads an .ico's own directory back, to prove it holds what was written.
func icoSizes(_ data: Data) -> [Int] {
    let b = [UInt8](data)
    guard b.count > 6, b[2] == 1, b[3] == 0 else { return [] }
    let n = Int(b[4]) | Int(b[5]) << 8
    return (0..<n).map { i in let w = Int(b[6 + i * 16]); return w == 0 ? 256 : w }
}

func text(_ ctx: CGContext, _ string: String, size: CGFloat, weight: NSFont.Weight, color: UInt32, x: CGFloat, baseline: CGFloat, height: Int) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font(size, weight), .foregroundColor: NSColor(cgColor: cg(color))!]))
    ctx.textPosition = CGPoint(x: x, y: CGFloat(height) - baseline)
    CTLineDraw(line, ctx)
}

/// The name in two tones: "Leaf" in leaf green, "Juice" in ink. Both are WCAG-checked before anything is drawn.
func wordmark(_ ctx: CGContext, size: CGFloat, dark: Bool, x: CGFloat, baseline: CGFloat, height: Int) {
    let f = font(size, .bold)
    let s = NSMutableAttributedString(string: "Leaf", attributes: [.font: f, .foregroundColor: NSColor(cgColor: cg(dark ? leafOnDark : leafOnLight))!])
    s.append(NSAttributedString(string: "Juice", attributes: [.font: f, .foregroundColor: NSColor(cgColor: cg(dark ? darkInk : ink))!]))
    ctx.textPosition = CGPoint(x: x, y: CGFloat(height) - baseline)
    CTLineDraw(CTLineCreateWithAttributedString(s), ctx)
}

let tagline = "A little pulp goes a long way."
let leafOnLight: UInt32 = 0x4A6E22, leafOnDark: UInt32 = 0xC3E491
let tagOnLight: UInt32 = 0xA33C25, tagOnDark: UInt32 = 0xFFB8A6

// Fonts come only from brand/fonts, each with its open licence beside it (owner, 2026-11-14: open-licence fonts only,
// always). A font without one stops the build. Lilita One for the name, Fredoka for everything else.
let fontsFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("brand/fonts", isDirectory: true)
var loadedFonts: [String: CTFontDescriptor] = [:]
func openFont(_ relative: String) -> CTFontDescriptor {
    if let d = loadedFonts[relative] { return d }
    let url = fontsFolder.appendingPathComponent(relative)
    let licence = (try? String(contentsOf: url.deletingLastPathComponent().appendingPathComponent("OFL.txt"), encoding: .utf8)) ?? ""
    guard licence.contains("SIL OPEN FONT LICENSE") else { fail("\(relative) has no open licence (OFL.txt) beside it, so it isn't used.") }
    guard let ds = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let d = ds.first else { fail("Can't read the font \(relative).") }
    loadedFonts[relative] = d
    return d
}

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    if weight >= .bold { return CTFontCreateWithFontDescriptor(openFont("lilitaone/LilitaOne-Regular.ttf"), size, nil) as NSFont }
    let fredoka = CTFontDescriptorCreateCopyWithVariation(openFont("fredoka/Fredoka[wdth,wght].ttf"), 0x77676874 as CFNumber, 600) // wght
    return CTFontCreateWithFontDescriptor(fredoka, size, nil) as NSFont
}

func width(_ string: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font(size, weight)]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// A wide image: the mark on the left and the name and tagline beside it, centred as a group.
/// How the mark sits on a banner: bare, or on the same square tile or circle as the profile marks.
enum Holder: String, CaseIterable { case bare, square, circle }

/// The tile's colours. Chosen on 2026-11-14: pistachio with a ring in the tagline's colour (`taglineRing`), which gives
/// the tile's edge 5.99:1 on cream and 8.00:1 on dark. The others were the options compared on the way there.
enum Accent: String, CaseIterable {
    case pistachio, pistachioRing = "pistachio-ring", grapefruitWash = "grapefruit-wash"
    /// Pistachio with a ring in the tagline's colour, or in the bottom trim's (owner, 2026-11-14).
    case taglineRing = "tagline-ring", trimRing = "trim-ring"
    var top: UInt32 { self == .grapefruitWash ? 0xFFE6DD : tileTop }
    var bottom: UInt32 { self == .grapefruitWash ? 0xFBC9B8 : tileBottom }
    /// The ring on each background, or nil. On dark, pistachio stands at 11.8:1 without one.
    func ring(dark: Bool) -> UInt32? {
        switch self {
        case .pistachio: nil
        case .pistachioRing: dark ? nil : 0x76845F
        case .grapefruitWash: dark ? nil : 0xA33C25
        case .taglineRing: dark ? tagOnDark : tagOnLight
        case .trimRing: brandOrange
        }
    }
}

/// Every banner's parts must sit inside this share of the width, or the build fails: nothing is ever cut off.
let bannerMargin: CGFloat = 0.06

/// A wide image: the mark and the name and tagline beside it, centred as a group. `markRight` puts the mark after the
/// text, away from the bottom-left corner where X and Bluesky put the profile picture. A tagline too wide for the
/// image goes onto two lines, and if that's still too wide, everything is scaled down to fit.
func banner(_ m: Mark, w: Int, h: Int, dark: Bool, showTagline: Bool = true, holder: Holder = .square,
            accent: Accent = .taglineRing, markRight: Bool = false, name: String = "banner") -> CGImage {
    let ctx = canvas(w, h)
    ctx.setFillColor(cg(dark ? darkBack : cream)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    // A band of the brand red-orange along the bottom.
    ctx.setFillColor(cg(brandOrange)); ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: max(4, CGFloat(h) * 0.025)))
    let W = CGFloat(w), H = CGFloat(h)
    let room = W * (1 - bannerMargin * 2)
    var scale: CGFloat = 1
    let lines = showTagline ? [tagline] : []
    func layout(_ s: CGFloat) -> (slot: CGFloat, gap: CGFloat, nameSize: CGFloat, tagSize: CGFloat, textWidth: CGFloat) {
        let slot = (H * (holder == .bare ? 0.5 : 0.62) * s).rounded(.down)
        let nameSize = H * 0.22 * s
        let nameWidth = width("LeafJuice", size: nameSize, weight: .bold)
        // The tagline is set to exactly the wordmark's width (owner, 2026-11-14).
        let tagSize = lines.isEmpty ? 0 : nameSize * nameWidth / max(1, lines.map { width($0, size: nameSize, weight: .medium) }.max()!)
        let textWidth = nameWidth
        return (slot, H * 0.08 * s, nameSize, tagSize, textWidth)
    }
    var L = layout(scale)
    while L.slot + L.gap + L.textWidth > room, scale > 0.4 { scale -= 0.02; L = layout(scale) }
    let group = L.slot + L.gap + L.textWidth
    let left = (W - group) / 2
    guard left >= W * bannerMargin - 1 else { fail("\(name) doesn't fit: it would be cut off at the edges.") }
    let slotX = markRight ? left + L.textWidth + L.gap : left
    let textX = markRight ? left : left + L.slot + L.gap
    let slotY = (H - L.slot) / 2
    let cell = ((holder == .bare ? L.slot : L.slot * (holder == .circle ? 0.6 : 0.7)) / CGFloat(m.size)).rounded(.down)
    let art = cell * CGFloat(m.size)
    if holder != .bare {
        let rect = CGRect(x: slotX, y: H - slotY - L.slot, width: L.slot, height: L.slot)
        let path = holder == .circle ? CGPath(ellipseIn: rect, transform: nil)
                                     : CGPath(roundedRect: rect, cornerWidth: L.slot * 0.2, cornerHeight: L.slot * 0.2, transform: nil)
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        gradient(ctx, accent.top, accent.bottom, rect)
        ctx.restoreGState()
        if let ring = accent.ring(dark: dark) {
            let line = max(2, L.slot * 0.02)
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            ctx.setStrokeColor(cg(ring)); ctx.setLineWidth(line * 2); ctx.addPath(path); ctx.strokePath()
            ctx.restoreGState()
        }
    }
    drawMark(m, in: ctx, x: (slotX + (L.slot - art) / 2).rounded(.down), y: (slotY + (L.slot - art) / 2).rounded(.down), cell: cell, height: h)
    // The name and tagline block, centred on the mark's middle.
    let lineGap = L.tagSize * 1.3
    let blockHeight = L.nameSize + (lines.isEmpty ? 0 : L.tagSize * 0.6 + lineGap * CGFloat(lines.count))
    let nameBaseline = H / 2 - blockHeight / 2 + L.nameSize * 0.8
    wordmark(ctx, size: L.nameSize, dark: dark, x: textX, baseline: nameBaseline, height: h)
    for (i, line) in lines.enumerated() {
        text(ctx, line, size: L.tagSize, weight: .medium, color: dark ? tagOnDark : tagOnLight, x: textX, baseline: nameBaseline + L.tagSize * 0.6 + lineGap * CGFloat(i + 1), height: h)
    }
    return ctx.makeImage()!
}

/// A release post: the mark, the name, and the version, for a release's announcement.
let releaseLine = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : "New version"
func release(_ m: Mark, w: Int, h: Int) -> CGImage {
    let ctx = canvas(w, h)
    ctx.setFillColor(cg(cream)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(cg(brandOrange)); ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h) * 0.03))
    let short = CGFloat(min(w, h)), H = CGFloat(h)
    // The mark on its square with the tagline-coloured ring, as on the banners.
    let slot = (short * 0.44).rounded(.down)
    let top = H * 0.1
    let rect = CGRect(x: (CGFloat(w) - slot) / 2, y: H - top - slot, width: slot, height: slot)
    let path = CGPath(roundedRect: rect, cornerWidth: slot * 0.2, cornerHeight: slot * 0.2, transform: nil)
    ctx.saveGState(); ctx.addPath(path); ctx.clip(); gradient(ctx, tileTop, tileBottom, rect)
    ctx.setStrokeColor(cg(tagOnLight)); ctx.setLineWidth(max(4, slot * 0.04)); ctx.addPath(path); ctx.strokePath(); ctx.restoreGState()
    let cell = (slot * 0.7 / CGFloat(m.size)).rounded(.down)
    let art = cell * CGFloat(m.size)
    drawMark(m, in: ctx, x: ((CGFloat(w) - art) / 2).rounded(.down), y: (top + (slot - art) / 2).rounded(.down), cell: cell, height: h)
    let nameSize = short * 0.11
    let nameW = width("LeafJuice", size: nameSize, weight: .bold)
    // The version line matches the name's width, like the tagline on the banners, up to a sensible size.
    let lineSize = min(short * 0.07, nameSize * nameW / max(1, width(releaseLine, size: nameSize, weight: .semibold)))
    let lineW = width(releaseLine, size: lineSize, weight: .semibold)
    let nameBaseline = top + slot + nameSize * 1.3
    wordmark(ctx, size: nameSize, dark: false, x: (CGFloat(w) - nameW) / 2, baseline: nameBaseline, height: h)
    text(ctx, releaseLine, size: lineSize, weight: .semibold, color: tagOnLight, x: (CGFloat(w) - lineW) / 2, baseline: nameBaseline + lineSize * 1.6, height: h)
    return ctx.makeImage()!
}

func svg(_ m: Mark, scale: Int) -> String {
    var out = #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(m.size * scale)" height="\#(m.size * scale)" viewBox="0 0 \#(m.size) \#(m.size)" shape-rendering="crispEdges" role="img" aria-label="GilaMonster: a pixel-art Gila monster, red-orange, salmon and amber beads on basalt">"#
    out += "\n<title>GilaMonster</title>\n"
    for (y, row) in m.cells.enumerated() {
        var x = 0
        while x < row.count {
            guard let hex = row[x] else { x += 1; continue }
            var run = 1
            while x + run < row.count, row[x + run] == hex { run += 1 }
            let fill = "#" + String(format: "%06X", hex)
            out += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(run)\" height=\"1\" fill=\"\(fill)\"/>\n"
            x += run
        }
    }
    return out + "</svg>\n"
}

func save(_ image: CGImage, _ url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("Couldn't encode \(url.lastPathComponent).") }
    do { try data.write(to: url) } catch { fail("Couldn't write \(url.path).") }
}

// MARK: Run

guard CommandLine.arguments.count >= 2 else { fail("Usage: swift scripts/brand-kit.swift <folder with mark.txt>") }
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let mark = readMark(folder.appendingPathComponent("mark.txt"))

// Checked first, and fails closed: nothing is written if any pair is short, in any kind of color vision.
var pairs: [Pair] = []
// The mark's outline carries the shape on the cream tile, so it has to stand off it.
let outline = mark.palette["o"] ?? ink
pairs.append(Pair(what: "mark outline on the cream tile", fg: outline, bg: tileTop, minimum: 3))
pairs.append(Pair(what: "mark outline on white", fg: outline, bg: surface, minimum: 3))
// The beads sit inside the outline, so they decorate rather than carry the shape. Their ratios are listed, not held.
let beads: [(Character, String)] = [("R", "red-orange"), ("S", "salmon"), ("A", "amber"), ("T", "turquoise")]
let failures = checkPairs(pairs)
guard failures.isEmpty else { fail("WCAG check failed, nothing written:\n  " + failures.joined(separator: "\n  ")) }

let out = folder.appendingPathComponent("out")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
// Files the LeafJuice kit wrote that this one doesn't, so nothing stale is left beside the new ones. Named one by one.
for name in ["LeafJuice.ico", "mark-circle-light-1024.png", "mark-circle-light-400.png", "mark-circle-dark-1024.png",
             "mark-circle-dark-400.png", "mark-square-light-1024.png", "mark-square-light-400.png", "mark-square-dark-1024.png",
             "mark-square-dark-400.png"] + (wordmarkReady ? [] : [
             "github-social-preview-light-1280x640.png", "github-social-preview-dark-1280x640.png",
             "readme-header-light-1280x320.png", "readme-header-dark-1280x320.png", "x-header-light-1500x500.png",
             "x-header-dark-1500x500.png", "bluesky-banner-light-3000x1000.png", "bluesky-banner-dark-3000x1000.png",
             "linkedin-banner-light-1584x396.png", "linkedin-banner-dark-1584x396.png",
             "linkedin-company-banner-light-1128x191.png", "linkedin-company-banner-dark-1128x191.png",
             "release-square-1080.png", "release-landscape-1200x675.png"]) {
    try? FileManager.default.removeItem(at: out.appendingPathComponent(name))
}
try! svg(mark, scale: 64).write(to: out.appendingPathComponent("mark.svg"), atomically: true, encoding: .utf8)
for circle in [true, false] {
    for size in [1024, 400] {
        save(profile(mark, size: size, circle: circle, dark: false), out.appendingPathComponent("mark-\(circle ? "circle" : "square")-\(size).png"))
    }
}
// The app icon from one master: icon.svg (and icon-small.svg for 16 to 32 px), drawn here as PNGs at every size.
try! iconSVG(mark, small: false).write(to: out.appendingPathComponent("icon.svg"), atomically: true, encoding: .utf8)
try! iconSVG(mark, small: true).write(to: out.appendingPathComponent("icon-small.svg"), atomically: true, encoding: .utf8)
func icon(_ size: Int) -> CGImage { size <= 32 ? smallIcon(mark, size: size) : appIcon(mark, size: size) }
save(icon(1024), out.appendingPathComponent("icon-1024.png"))
save(icon(32), out.appendingPathComponent("icon-32.png"))
// macOS: an iconset of every size and scale, then iconutil.
let iconset = out.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    save(icon(base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    save(icon(base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run(); iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil couldn't make the .icns.") }
try? FileManager.default.removeItem(at: iconset)
// Windows: the sizes Explorer and the taskbar ask for.
let icoSizesWanted = [16, 24, 32, 48, 64, 128, 256]
let icoData = ico(icoSizesWanted.map { ($0, png(icon($0))) })
try! icoData.write(to: out.appendingPathComponent("GilaMonster.ico"))
guard icoSizes(icoData) == icoSizesWanted else { fail("The .ico didn't read back with every size.") }
// The menu-bar template: every drawn pixel of the mark in black on clear, one art pixel per point. macOS tints a
// template itself, for light and dark menu bars and for Increase Contrast, so it carries no color of its own.
func menuBarTemplate(scale: Int) -> CGImage {
    let size = mark.size * scale
    let ctx = canvas(size, size)
    ctx.setShouldAntialias(false)
    ctx.setFillColor(cg(0x000000))
    for (row, cells) in mark.cells.enumerated() {
        for (col, hex) in cells.enumerated() where hex != nil {
            ctx.fill(CGRect(x: col * scale, y: size - (row + 1) * scale, width: scale, height: scale))
        }
    }
    return ctx.makeImage()!
}
save(menuBarTemplate(scale: 1), out.appendingPathComponent("MenuBarTemplate.png"))
save(menuBarTemplate(scale: 2), out.appendingPathComponent("MenuBarTemplate@2x.png"))
if wordmarkReady {
    for dark in [false, true] {
        let tone = dark ? "dark" : "light"
        save(banner(mark, w: 1280, h: 640, dark: dark), out.appendingPathComponent("github-social-preview-\(tone)-1280x640.png"))
        save(banner(mark, w: 1280, h: 320, dark: dark), out.appendingPathComponent("readme-header-\(tone)-1280x320.png"))
        save(banner(mark, w: 1500, h: 500, dark: dark), out.appendingPathComponent("x-header-\(tone)-1500x500.png"))
        save(banner(mark, w: 3000, h: 1000, dark: dark), out.appendingPathComponent("bluesky-banner-\(tone)-3000x1000.png"))
        save(banner(mark, w: 1584, h: 396, dark: dark), out.appendingPathComponent("linkedin-banner-\(tone)-1584x396.png"))
        save(banner(mark, w: 1128, h: 191, dark: dark, showTagline: false), out.appendingPathComponent("linkedin-company-banner-\(tone)-1128x191.png"))
    }
    save(release(mark, w: 1080, h: 1080), out.appendingPathComponent("release-square-1080.png"))
    save(release(mark, w: 1200, h: 675), out.appendingPathComponent("release-landscape-1200x675.png"))
    // Bluesky refuses images over 1,000,000 bytes (its lexicon limit), so a banner that grows past it fails the build.
    for name in ["bluesky-banner-light-3000x1000.png", "bluesky-banner-dark-3000x1000.png"] {
        let size = (try? FileManager.default.attributesOfItem(atPath: out.appendingPathComponent(name).path)[.size] as? Int) ?? 0
        if size > 1_000_000 { fail("\(name) is \(size) bytes, over Bluesky's 1,000,000-byte limit.") }
    }
}
// The adopted icon (owner, 2026-11-23, D276) goes where the app build and the README look for it: brand/.
let brandFolder = folder.deletingLastPathComponent()
for name in ["AppIcon.icns", "GilaMonster.ico", "icon.svg", "icon-small.svg", "icon-1024.png",
             "MenuBarTemplate.png", "MenuBarTemplate@2x.png"] {
    let target = brandFolder.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: target)
    try! FileManager.default.copyItem(at: out.appendingPathComponent(name), to: target)
}
print("Wrote the kit to \(out.path). WCAG: \(pairs.count) pairs passed in every kind of color vision.")
for p in pairs { let (r, v) = lowest(p); print("  \(p.what): \(String(format: "%.2f", contrast(p.fg, p.bg))):1, lowest \(String(format: "%.2f", r)):1 (\(v.rawValue))") }
print("Beads on the basalt body (decoration, not held):")
for (key, name) in beads { if let hex = mark.palette[key] { let (r, v) = lowest(Pair(what: name, fg: hex, bg: outline, minimum: 0)); print("  \(name): \(String(format: "%.2f", contrast(hex, outline))):1, lowest \(String(format: "%.2f", r)):1 (\(v.rawValue))") } }
