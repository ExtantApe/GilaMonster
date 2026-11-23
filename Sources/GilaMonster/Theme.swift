import AppKit
import GilaMonsterCore
import SwiftUI

/// The GilaMonster palette: cream and basalt, turquoise for structure and red-orange as the one bold pop (D272, D277).
/// The colors live in `Palette` (GilaMonsterCore), so a new palette is one file of numbers; these names never change.
/// Every pair meets WCAG AA in all four appearances and under common color blindness, checked by gilamonster-check
/// against `Palette` (see docs/ux-audit.md).
/// State is always shown by shape and word as well as color.
enum Theme {
    static let background = dynamic(Palette.background)
    static let surface = dynamic(Palette.surface)
    static let raised = dynamic(Palette.raised)
    /// Card outlines and dividers only. Buttons and fields use controlBorder.
    static let border = dynamic(Palette.border)
    static let controlBorder = dynamic(Palette.controlBorder)
    static let ink = dynamic(Palette.ink)
    static let muted = dynamic(Palette.muted)
    /// Structure, such as icons, toggles, selection, links and focus.
    static let accent = dynamic(Palette.accent)
    static let accentWash = dynamic(Palette.accentWash)
    /// The pop. Only for the main action on a page.
    static let pop = dynamic(Palette.pop)
    static let onPop = dynamic(Palette.onPop)
    /// The pop as a text color, and the main button's outline.
    static let popText = dynamic(Palette.popText)
    static let warning = dynamic(Palette.warning)
    static let warningWash = dynamic(Palette.warningWash)
    static let danger = dynamic(Palette.danger)
    static let dangerWash = dynamic(Palette.dangerWash)
    static let info = dynamic(Palette.info)
    static let infoWash = dynamic(Palette.infoWash)
    /// Plugin source badge colours, by SourceKind raw value: (tint, icon accent).
    static let sourceColors: [String: (wash: Color, accent: Color)] = Dictionary(uniqueKeysWithValues:
        Palette.sources.map { ($0.name, (dynamic($0.wash), dynamic($0.accent))) })

    static let controlHeight: CGFloat = 32
    static let controlRadius: CGFloat = 8
    static let cardRadius: CGFloat = 10

    /// The palette's numbers live in GilaMonsterCore, where `gilamonster-check` holds every pair to WCAG AA.
    private static func dynamic(_ swatch: Palette.Swatch) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            switch match {
            case .accessibilityHighContrastAqua: return nsColor(swatch.contrastLight)
            case .accessibilityHighContrastDarkAqua: return nsColor(swatch.contrastDark)
            case .darkAqua: return nsColor(swatch.dark)
            default: return nsColor(swatch.light)
            }
        })
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Buttons

struct ThemeButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            configuration.label
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(.body.weight(kind == .primary ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(minHeight: Theme.controlHeight)
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(borderColor, lineWidth: 1)
                }
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: Theme.controlRadius + 2).strokeBorder(Theme.accent, lineWidth: 2).padding(-3)
                    }
                }
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.onPop
            case .secondary: Theme.ink
            case .danger: Theme.danger
            }
        }
        private var fill: Color {
            switch kind {
            case .primary: Theme.pop
            case .secondary: hovering && enabled ? Theme.raised : Theme.surface
            case .danger: hovering && enabled ? Theme.dangerWash : Theme.surface
            }
        }
        private var borderColor: Color {
            switch kind {
            case .primary: Theme.popText
            case .secondary: Theme.controlBorder
            case .danger: Theme.danger
            }
        }
    }
}

extension ButtonStyle where Self == ThemeButtonStyle {
    static var themed: ThemeButtonStyle { ThemeButtonStyle() }
    static var themedPrimary: ThemeButtonStyle { ThemeButtonStyle(kind: .primary) }
    static var themedDanger: ThemeButtonStyle { ThemeButtonStyle(kind: .danger) }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                } icon: {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(Theme.accent) }
                }
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border, lineWidth: 1) }
    }
}

/// A scrolling page with a consistent title and width.
struct Page<Content: View>: View {
    let title: String
    var subtitle: String?
    var oneLineSubtitle = false
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeading(title: title, subtitle: subtitle, oneLine: oneLineSubtitle)
                content
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PageHeading: View {
    let title: String
    var subtitle: String?
    var oneLine = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.largeTitle.weight(.semibold)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            if let subtitle {
                if oneLine {
                    Text(subtitle).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).help(subtitle)
                } else {
                    Text(subtitle).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

enum Tone {
    case good, warning, danger, info, neutral
    var color: Color {
        switch self {
        case .good: Theme.accent
        case .warning: Theme.warning
        case .danger: Theme.danger
        case .info: Theme.info
        case .neutral: Theme.muted
        }
    }
    var wash: Color {
        switch self {
        case .good: Theme.accentWash
        case .warning: Theme.warningWash
        case .danger: Theme.dangerWash
        case .info: Theme.infoWash
        case .neutral: Theme.raised
        }
    }
    var icon: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        case .neutral: "circle.dashed"
        }
    }
}

/// A short status: icon, word and color together, so it never relies on color alone.
struct Badge: View {
    let text: String
    var tone: Tone = .neutral
    var icon: String?

    var body: some View {
        Label {
            Text(text).font(.caption.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1).fixedSize()
        } icon: {
            Image(systemName: icon ?? tone.icon).font(.caption).foregroundStyle(tone.color)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tone.wash, in: Capsule())
    }
}

/// A full-width message with an optional action.
struct Callout<Actions: View>: View {
    let tone: Tone
    let title: String
    var detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.icon).foregroundStyle(tone.color).font(.title3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                if let detail { Text(detail).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.wash, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(tone.color.opacity(0.6), lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}

extension Callout where Actions == EmptyView {
    init(tone: Tone, title: String, detail: String? = nil) {
        self.init(tone: tone, title: title, detail: detail) { EmptyView() }
    }
}

struct EmptyMessage: View {
    let icon: String
    let title: String
    var detail: String?
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(Theme.ink)
            if let detail { Text(detail).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// A label and value in a form-like row.
struct Fact: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
    }
}

extension ServerState {
    var tone: Tone {
        switch self {
        case .running: .good
        case .starting, .stopping: .info
        case .stopped: .neutral
        case .crashed: .danger
        case .external: .warning
        }
    }
    var icon: String {
        switch self {
        case .running: "play.circle.fill"
        case .starting, .stopping: "hourglass.circle.fill"
        case .stopped: "stop.circle"
        case .crashed: "xmark.octagon.fill"
        case .external: "exclamationmark.triangle.fill"
        }
    }
}

extension Severity {
    var tone: Tone {
        switch self {
        case .critical, .error: .danger
        case .warning: .warning
        case .info: .info
        }
    }
    var icon: String {
        switch self {
        case .critical: "xmark.octagon.fill"
        case .error: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }
}

extension Compatibility.Verdict {
    var tone: Tone {
        switch self {
        case .compatible: .good
        case .likely: .info
        case .unknown: .neutral
        case .incompatible: .danger
        }
    }
    var title: String {
        switch self {
        case .compatible: "Compatible"
        case .likely: "Likely"
        case .unknown: "Unknown"
        case .incompatible: "Incompatible"
        }
    }
}

extension ServerController {
    /// Runs work and surfaces any failure in the page's notice banner.
    func attempt(_ work: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await work() } catch { notice = error.localizedDescription }
        }
    }
}

/// Where a plugin comes from, as two badges side by side: the source, tinted with its own colour and icon, and the
/// project there, outlined (owner, 2026-11-15). VoiceOver reads them as one: "Source Modrinth, ID luckperms".
struct SourceBadges: View {
    let source: PluginSource

    var body: some View {
        if let b = source.badge {
            let colors = Theme.sourceColors[source.kind.rawValue] ?? (Theme.raised, Theme.muted)
            HStack(spacing: 4) {
                Label {
                    Text(b.source).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1).fixedSize()
                } icon: {
                    Image(systemName: source.kind.symbol).font(.caption).foregroundStyle(colors.accent)
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(colors.wash, in: Capsule())
                Text(b.id).font(.caption.monospaced()).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay { Capsule().strokeBorder(Theme.controlBorder, lineWidth: 1) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(source.spoken)
        } else {
            Badge(text: "No source", tone: .neutral)
        }
    }
}

extension SourceKind {
    /// Each source's icon, so the badge doesn't rest on its colour.
    var symbol: String {
        switch self {
        case .none: "circle.dashed"
        case .modrinth: "shippingbox.fill"
        case .hangar: "paperplane.fill"
        case .spigot: "drop.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .jenkins: "hammer.fill"
        case .web: "globe"
        }
    }
}

/// Disables a control and says why, as a tooltip and a VoiceOver hint, so a grey button is never a mystery
/// (UX audit 2026-11-15, finding 3). Nil means enabled. Busy states can still use plain `.disabled`.
struct DisabledBecause: ViewModifier {
    let reason: String?
    func body(content: Content) -> some View {
        if let reason {
            content.disabled(true).help(reason).accessibilityHint(reason)
        } else {
            content
        }
    }
}

extension View {
    func disabled(because reason: String?) -> some View { modifier(DisabledBecause(reason: reason)) }
}
