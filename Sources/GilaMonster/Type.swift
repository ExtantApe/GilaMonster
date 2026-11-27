import AppKit
import CoreText
import GilaMonsterCore
import SwiftUI

// Pixel type (K820). The rules are `PixelType` in GilaMonsterCore, where the checks hold them. This file reads what
// the Mac and the setting say, and turns each answer into a font.

/// What the type rules need to know right now: the Pixel font setting, the system's body size, Bold Text, the screen's
/// pixels per point, and whether the two faces loaded. Views read it through `TypeToken` and `Theme.grow`, so they
/// redraw when any of it changes.
@Observable final class TypeState: @unchecked Sendable {
    static let shared = TypeState()

    /// The Pixel font setting.
    var on = true
    /// The system's resolved body size.
    var bodySize = PixelType.defaultBody
    /// Bold Text, as SwiftUI reports it to the windows.
    var boldText = false
    var departureLoaded = false
    var pixelifyLoaded = false
    /// Pixels per point of each open window, by the window's own id. Text has to be sharp in all of them, so the
    /// smallest one decides.
    private var scales: [UUID: Double] = [:]
    /// Used until a window reports its own.
    private var screenScale = 2.0
    /// A snapshot sets everything itself and windows don't report.
    @ObservationIgnored private(set) var fixed = false
    @ObservationIgnored private var settled = false

    var conditions: PixelType.Conditions {
        PixelType.Conditions(on: on, departureLoaded: departureLoaded, pixelifyLoaded: pixelifyLoaded, bodySize: bodySize, boldText: boldText,
                             scale: scales.values.min() ?? screenScale)
    }

    /// The body size macOS resolves for this app. It follows Text Size where the system applies it.
    static var systemBodySize: Double { Double(NSFont.preferredFont(forTextStyle: .body).pointSize) }
    static var screenScales: [Double] { NSScreen.screens.map { Double($0.backingScaleFactor) } }

    /// Once at launch, after the fonts are registered. The setting is read without being saved: the first window
    /// settles it, because only a window knows whether Bold Text is on.
    func start() {
        departureLoaded = BrandFonts.departureLoaded
        pixelifyLoaded = BrandFonts.pixelifyLoaded
        bodySize = Self.systemBodySize
        screenScale = Double(NSScreen.main?.backingScaleFactor ?? 2)
        on = PixelType.load(bodySize: bodySize, boldText: false, screenScales: Self.screenScales, remember: false)
    }

    /// A window says what it sees. The first one to do so settles the setting's first-launch default and saves it.
    func report(window: UUID, scale: Double, boldText: Bool) {
        guard !fixed else { return }
        if scales[window] != scale { scales[window] = scale }
        if self.boldText != boldText { self.boldText = boldText }
        refreshBodySize()
        if !settled {
            settled = true
            let start = PixelType.load(bodySize: bodySize, boldText: boldText, screenScales: Self.screenScales, remember: true)
            if on != start { on = start }
        }
    }

    func closed(window: UUID) {
        guard !fixed else { return }
        scales[window] = nil
    }

    func refreshBodySize() {
        guard !fixed else { return }
        let size = Self.systemBodySize
        if bodySize != size { bodySize = size }
    }

    #if DEBUG
    /// Snapshots only: stands in for what the Mac would say, and saves nothing. The rules that follow are the real ones.
    func fix(on: Bool?, bodySize: Double?, boldText: Bool, scale: Double) {
        fixed = true
        self.bodySize = bodySize ?? PixelType.defaultBody
        self.boldText = boldText
        screenScale = scale
        scales = [:]
        self.on = on ?? PixelType.firstLaunchDefault(bodySize: self.bodySize, boldText: boldText, screenScales: [scale])
    }
    #endif
}

/// Put on the root of each window: it tells `TypeState` the window's pixels per point and Bold Text, again whenever
/// either changes (a window dragged to another screen re-snaps the sizes), and sets the window's base font.
struct TypeRoot: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var window = UUID()

    func body(content: Content) -> some View {
        content
            .font(TypeToken.body.font)
            .disclosureGroupStyle(ThemedDisclosureStyle())
            .onAppear { report() }
            .onChange(of: displayScale) { report() }
            .onChange(of: legibilityWeight) { report() }
            .onDisappear { TypeState.shared.closed(window: window) }
            // Text Size is changed in System Settings, so coming back to the app is when to look again.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in TypeState.shared.refreshBodySize() }
    }

    private func report() { TypeState.shared.report(window: window, scale: Double(displayScale), boldText: legibilityWeight == .bold) }
}

extension View {
    func typeRoot() -> some View { modifier(TypeRoot()) }
}

extension Theme {
    /// How much controls, paddings, column widths, the sidebar, switches and symbols grow with the text. 1 at the
    /// default text size.
    static var grow: CGFloat { CGFloat(TypeState.shared.conditions.grow) }
    /// The system's text size over its default, for things sized by wrapping text.
    static var textFactor: CGFloat { CGFloat(max(1, TypeState.shared.conditions.factor)) }

    /// The font for an SF Symbol beside a label, so status symbols and chevrons grow with the labels.
    static func symbol(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        let grow = Theme.grow
        guard grow != 1 else { return Font.system(style).weight(weight) }
        return .system(size: TypeToken.systemSize(style) * grow, weight: weight)
    }

}

/// A text style and the font it uses now. Apply with `.type(.label())`.
struct TypeToken {
    let resolved: PixelType.Resolved
    let font: Font
    /// The drawn point size, for symbols set beside it in the system font.
    var size: CGFloat { CGFloat(resolved.size) }
    var isPixel: Bool { resolved.isPixel }

    /// Long text: sentences, help, explanations, errors. Always the system font.
    static var body: TypeToken { make(.body, .body) }
    /// Short labels, buttons, badges, tabs and row titles.
    static func label(_ weight: Font.Weight = .regular) -> TypeToken { make(.label(core(weight)), .body) }
    /// Card and group headings.
    static var headline: TypeToken { make(.heading, .headline) }
    /// A fact card's quiet heading: the same capitals, and the semibold body font when labels are in the system font.
    static var factHeading: TypeToken { let heading = headline; return heading.resolved.caps ? heading : label(.semibold) }
    /// Titles by their system size: 26 is a screen's one title, 17 a sheet's, 15 a section's.
    static func title(_ points: CGFloat, _ style: Font.TextStyle) -> TypeToken {
        make(points >= 22 ? .screenTitle(Double(points)) : .title(Double(points)), style)
    }
    /// A status sentence or a name that is its screen's title.
    static func display(_ points: CGFloat) -> TypeToken { make(.display(Double(points)), nil) }
    /// The Allow prompt's sentence.
    static var prompt: TypeToken { make(.promptSentence, nil) }
    /// Counts, sizes, clocks and addresses.
    static var number: TypeToken { make(.number, .body) }
    /// A value beside a label: a number when it starts with a digit, a label otherwise.
    static func value(_ text: String) -> TypeToken { text.first?.isNumber == true ? number : label() }
    /// Logs, commands and ids.
    static var mono: TypeToken { make(.mono, .body) }

    /// The system's own sizes at the default Text Size.
    static func systemSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        case .callout: 12
        default: 13
        }
    }

    private static func core(_ weight: Font.Weight) -> PixelType.Weight {
        switch weight {
        case .bold, .heavy, .black: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
    }

    private static func weight(_ weight: PixelType.Weight) -> Font.Weight {
        switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    private static func make(_ role: PixelType.Role, _ style: Font.TextStyle?) -> TypeToken {
        let conditions = TypeState.shared.conditions
        let resolved = PixelType.resolve(role, conditions)
        return TypeToken(resolved: resolved, font: font(resolved, style: style, atDefault: abs(conditions.factor - 1) < 0.0001))
    }

    /// The one place a face becomes a font. Every pixel face falls back to the system font if it can't be made, and
    /// carries the system font as its fallback for any character it lacks, so text is never lost.
    private static func font(_ resolved: PixelType.Resolved, style: Font.TextStyle?, atDefault: Bool) -> Font {
        let size = CGFloat(resolved.size)
        func system(design: Font.Design = .default) -> Font {
            // At the default size this is the system's own text style, exactly as before the pixel type.
            let base: Font = if atDefault, let style { Font.system(style, design: design).weight(weight(resolved.weight)) }
                             else { Font.system(size: size, weight: weight(resolved.weight), design: design) }
            return resolved.tabularDigits ? base.monospacedDigit() : base
        }
        switch resolved.face {
        case .system: return system()
        case .systemMono: return system(design: .monospaced)
        case .lilita: return Theme.display(size)
        case .departure: return BrandFonts.pixel(PixelType.departureName, size: size, weight: nil) ?? system()
        case .pixelify: return BrandFonts.pixel(PixelType.pixelifyName, size: size, weight: 700) ?? system()
        }
    }
}

extension View {
    /// Sets the font, and for card headings the capitals and their one pixel of extra spacing.
    @ViewBuilder func type(_ token: TypeToken) -> some View {
        if token.resolved.caps {
            font(token.font).tracking(CGFloat(token.resolved.tracking)).textCase(.uppercase)
        } else {
            font(token.font)
        }
    }
}

/// Text whose shortcut signs, arrows, ticks and small triangles are set in the system font on purpose
/// (`PixelType.symbols`), so a pixel face that lacks them never leaves it to font fallback.
struct SymbolText: View {
    let text: String
    let token: TypeToken
    init(_ text: String, _ token: TypeToken) { self.text = text; self.token = token }

    var body: some View {
        PixelType.runs(text).reduce(Text("")) { joined, run in
            joined + Text(run.text).font(run.symbol ? .system(size: token.size) : token.font)
        }
    }
}

/// Buttons side by side whenever they fit at full size, stacked only when they don't. Their padding never shrinks.
struct WrapRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }
}

extension BrandFonts {
    nonisolated(unsafe) private static var made: [String: NSFont] = [:]
    private static let madeLock = NSLock()

    /// A pixel face at a size, with the system font named as its fallback. Nil when the face isn't there.
    static func pixel(_ name: String, size: CGFloat, weight: Int?) -> Font? {
        let key = "\(name) \(size) \(weight ?? 0)"
        madeLock.lock()
        defer { madeLock.unlock() }
        if let known = made[key] { return Font(known as CTFont) }
        guard FontFiles.isAvailable(name), let base = NSFont(name: name, size: size) else { return nil }
        var attributes: [NSFontDescriptor.AttributeName: Any] = [.cascadeList: [NSFont.systemFont(ofSize: size).fontDescriptor]]
        // Pixelify Sans is a variable font: 700 is a real weight on its 'wght' axis.
        if let weight { attributes[.variation] = [0x7767_6874: weight] }
        let font = NSFont(descriptor: base.fontDescriptor.addingAttributes(attributes), size: size) ?? base
        made[key] = font
        return Font(font as CTFont)
    }
}
