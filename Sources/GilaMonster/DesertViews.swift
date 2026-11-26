import AppKit
import CoreText
import GilaMonsterCore
import SwiftUI

// The desert look, calmed down (K786, owner's pick 2026-11-25: "B: desert base, calmed down"): the basalt spine with
// five section beads, the trail of a section's pages, pixel status glyphs, made-up faces and the Allow prompt's band.

// MARK: - Fonts

/// The brand's display face, loaded from the app's own Resources/Fonts, or from brand/fonts in a debug build. Only
/// SIL OFL fonts, with their licence beside them (brand/fonts/lilitaone/OFL.txt).
enum BrandFonts {
    static let lilita = "LilitaOne"
    nonisolated(unsafe) private(set) static var lilitaLoaded = false

    static func register() {
        guard !lilitaLoaded else { return }
        let file = "LilitaOne-Regular.ttf"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("Fonts/\(file)")) }
        #if DEBUG
        // A debug build runs straight from .build, so it reads the font from the repo it was built from.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(repo.appendingPathComponent("brand/fonts/lilitaone/\(file)"))
        #endif
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) || NSFont(name: lilita, size: 12) != nil {
                lilitaLoaded = NSFont(name: lilita, size: 12) != nil
                if lilitaLoaded { return }
            }
        }
    }
}

// MARK: - Pixel art

/// A grid of square pixels, drawn crisp at any size.
private struct PixelGrid: View {
    let width: Int
    let height: Int
    let cells: [(x: Int, y: Int, color: Color)]

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / CGFloat(width), size.height / CGFloat(height))
            let ox = (size.width - unit * CGFloat(width)) / 2, oy = (size.height - unit * CGFloat(height)) / 2
            // One path per color, so neighbouring pixels join without hairline seams.
            var runs: [(color: Color, path: Path)] = []
            for cell in cells {
                let rect = CGRect(x: ox + CGFloat(cell.x) * unit, y: oy + CGFloat(cell.y) * unit, width: unit, height: unit)
                if let i = runs.firstIndex(where: { $0.color == cell.color }) { runs[i].path.addRect(rect) }
                else { var path = Path(); path.addRect(rect); runs.append((cell.color, path)) }
            }
            for run in runs { context.fill(run.path, with: .color(run.color)) }
        }
        .accessibilityHidden(true)
    }
}

extension PixelGlyph {
    var color: Color {
        switch self {
        case .up: Theme.up
        case .starting: Theme.starting
        case .down: Theme.danger
        case .stopped: Theme.stopped
        }
    }
}

/// One 8 by 8 status glyph in its state's color. Decoration for VoiceOver: the word next to it is what's read.
struct GlyphView: View {
    let glyph: PixelGlyph
    var size: CGFloat = 14
    var color: Color?
    var body: some View {
        PixelGrid(width: 8, height: 8, cells: glyph.pixels.map { ($0.x, $0.y, color ?? glyph.color) })
            .frame(width: size, height: size)
    }
}

/// A state as its glyph and its word together.
struct StateLabel: View {
    let state: ServerState
    var font: Font = .body.weight(.semibold)
    var body: some View {
        HStack(spacing: 5) {
            GlyphView(glyph: state.glyph)
            Text(state.title).font(font).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A made-up 8 by 8 face for a player, from their name. Nothing is fetched.
struct FaceView: View {
    let name: String
    var size: CGFloat = 28
    var body: some View {
        let colors = PixelFace.pixels(name)
        PixelGrid(width: 8, height: 8, cells: colors.enumerated().map { ($0.offset % 8, $0.offset / 8, Theme.art($0.element)) })
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(2, size / 10)))
    }
}

/// The icon's lizard on its cream tile, as the icon draws it. Decoration.
struct LizardView: View {
    var body: some View {
        let cells = PixelLizard.rows.enumerated().flatMap { y, row in
            row.enumerated().compactMap { x, c in PixelLizard.colors[c].map { (x, y, Theme.art($0)) } }
        }
        PixelGrid(width: 14, height: 16, cells: cells)
            .frame(width: 22, height: 25)
            .frame(width: 40, height: 40)
            .background(Theme.lizardTile, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

/// The thin bead band on top of the Allow prompt: brand.md's tile at half size, repeated. Decoration.
struct BeadBandView: View {
    var height: CGFloat = 6
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.art(BeadBand.ground)))
            let scale = height / 12, tile = BeadBand.tileWidth * scale
            var x0: CGFloat = 0
            while x0 < size.width + tile {
                for bead in BeadBand.beads {
                    let r = BeadBand.radius * scale
                    let rect = CGRect(x: x0 + bead.x * scale - r, y: bead.y * scale - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.art(bead.color)))
                }
                x0 += tile
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Spine

/// The basalt spine down the window's left edge: the lizard, the server switcher and one bead per section.
/// The beads are a tab list named Sections: ↑↓ move between them, Return or Space picks one, and ⌥⌘1 to ⌥⌘5 pick one
/// from anywhere.
struct Spine: View {
    @Bindable var model: AppModel
    let server: ServerController
    @Binding var renaming: Bool
    @FocusState private var focused: String?

    var body: some View {
        VStack(spacing: 14) {
            LizardView()
            ServerSwitcher(model: model, server: server, renaming: $renaming)
            VStack(spacing: 10) {
                ForEach(model.shownSections) { bead($0) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")
            .accessibilityAddTraits(.isTabBar)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .background(Theme.spine)
    }

    private func bead(_ section: Sections.Section) -> some View {
        let on = model.currentSection.id == section.id
        let waiting = Sections.badge(section, badges: model.badges(server))
        let pages = model.pages(in: section).count
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 9)
                .fill(on ? Theme.beadOn : Theme.beadIdle)
                .frame(width: 32, height: 32)
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Theme.beadRing : Theme.beadEdge, lineWidth: on ? 2 : 1.5) }
                .overlay(alignment: .topTrailing) {
                    if waiting > 0 {
                        Text("\(waiting)").font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.onPill)
                            .padding(.horizontal, 5).background(Theme.pill, in: Capsule())
                            .offset(x: 10, y: -7)
                    }
                }
            Text(section.title)
                .font(.body.weight(on ? .bold : .regular))
                .foregroundStyle(on ? Theme.spineInk : Theme.spineMuted)
                .lineLimit(1).fixedSize()
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .overlay {
            if focused == section.id {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.spineFocus, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused, equals: section.id)
        .onTapGesture { model.choose(section) }
        .onKeyPress(keys: [.return, .space]) { _ in model.choose(section); return .handled }
        .onKeyPress(.upArrow) { move(from: section, by: -1); return .handled }
        .onKeyPress(.downArrow) { move(from: section, by: 1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Sections.spoken(section.title, pages: pages, waiting: waiting))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.choose(section) }
        .help("\(section.title) (⌥⌘\((Sections.all.firstIndex(of: section) ?? 0) + 1))")
    }

    private func move(from section: Sections.Section, by offset: Int) {
        let ids = model.shownSections.map(\.id)
        guard let next = Sections.step(from: section.id, in: ids, by: offset) else { return }
        focused = next
    }
}

/// The server switcher at the top of the spine: the server's icon (or its first letters) with its state glyph on top.
/// The menu lists every server with its state in words.
struct ServerSwitcher: View {
    @Bindable var model: AppModel
    let server: ServerController
    @Binding var renaming: Bool
    @State private var icon: NSImage?

    /// A state icon that keeps its colour in a menu. Menus draw plain symbols in one colour, so this one is drawn
    /// coloured and marked as not a template.
    static func menuIcon(_ state: ServerState) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(state.tone.color)]))
        let image = NSImage(systemSymbolName: state.icon, accessibilityDescription: state.title)?.withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }

    var body: some View {
        Menu {
            // Each server with its state before choosing it (owner, 2026-11-15): the state's own icon in its colour, and
            // its name in words, so it doesn't rest on colour alone. The current one keeps the menu's checkmark.
            ForEach(model.listed) { other in
                Toggle(isOn: Binding(get: { other.id == server.id }, set: { if $0 { model.selectedID = other.id } })) {
                    Label {
                        Text("\(other.profile.name)\(other.isLab ? " (for this run)" : "") · \(other.state.title)")
                    } icon: {
                        Image(nsImage: Self.menuIcon(other.state))
                    }
                }
                .accessibilityLabel("\(other.profile.name)\(other.isLab ? ", the Lab's server for this run" : ""), \(other.state.title)")
            }
            Divider()
            Button("Add Server…") { model.showAddServer = true }
            if Modules.shared.isOn(.lab), model.lab.model(from: model.servers) != nil {
                Button("Open the Lab") { model.openLabBoard() }
            }
            if !server.isLab { Button("Rename \(server.profile.name)…") { renaming = true } }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let icon {
                            Image(nsImage: icon).interpolation(.none).resizable()
                        } else {
                            Text(PixelFace.initials(server.profile.name)).font(.body.weight(.bold)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.surface)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.beadEdge, lineWidth: 1) }
                    GlyphView(glyph: server.state.glyph, size: 12)
                        .padding(2).background(Theme.surface, in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: 5, y: 5)
                }
                Text("\(server.profile.name) ▾").accessibilityHidden(true).font(.body).foregroundStyle(Theme.spineMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 70)
            }
            .frame(width: 70)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Server: \(server.profile.name), \(server.state.title). Switch server.")
        .help("\(server.profile.name), \(server.state.title). Switch server.")
        .task(id: server.id) { icon = NSImage(contentsOf: ServerIcons.active(server.paths)) }
    }
}

// MARK: - Trail

/// The chosen section's pages as tabs across the top. ←→ move between them when one has focus, and ⌃Tab and ⌃⇧Tab move
/// along the trail from anywhere. A new section's trail slides in from the left over 160 ms, at once with Reduce Motion.
struct Trail: View {
    @Bindable var model: AppModel
    let server: ServerController
    @FocusState private var focused: PageID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let section = model.currentSection
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 22) {
                ForEach(model.pages(in: section)) { tab($0) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .id(section.id)
            .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
        }
        .frame(height: 40, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: section.id)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1).accessibilityHidden(true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.title) pages")
        .accessibilityAddTraits(.isTabBar)
        // A section change swaps the tabs, so a tab that had focus would vanish and take focus with it. Keep focus on
        // the trail, on the new section's chosen page (accessibility review, K786).
        .onChange(of: section.id) { if focused != nil { DispatchQueue.main.async { focused = model.visiblePage } } }
    }

    private func tab(_ page: PageID) -> some View {
        let on = model.visiblePage == page
        let count = model.badge(for: page, server: server)
        return HStack(spacing: 5) {
            Text(page.title)
                .font(.body.weight(on ? .semibold : .medium))
                .foregroundStyle(on ? Theme.ink : Theme.muted)
            if count > 0 {
                Text("\(count)").font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).background(Theme.accentWash, in: Capsule())
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            if on { Rectangle().fill(Theme.popText).frame(height: 3).accessibilityHidden(true) }
        }
        .overlay {
            if focused == page {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: 2).padding(.horizontal, -6).padding(.top, -4).padding(.bottom, 4)
            }
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused, equals: page)
        .onTapGesture { model.page = page }
        .onKeyPress(keys: [.return, .space]) { _ in model.page = page; return .handled }
        .onKeyPress(.leftArrow) { step(page, -1); return .handled }
        .onKeyPress(.rightArrow) { step(page, 1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? "\(page.title), \(count) waiting" : page.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.page = page }
    }

    private func step(_ page: PageID, _ offset: Int) {
        let keys = model.pages(in: model.currentSection).map(\.rawValue)
        if let next = Sections.step(from: page.rawValue, in: keys, by: offset).flatMap(PageID.init(rawValue:)) { focused = next }
    }
}

// MARK: - Cards

/// A quiet fact card: a muted heading, a hairline edge and no shadow.
struct FactCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.muted).accessibilityAddTraits(.isHeader)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border, lineWidth: 1) }
    }
}
