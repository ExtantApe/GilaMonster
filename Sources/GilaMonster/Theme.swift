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
    static let up = dynamic(Palette.up)
    static let starting = dynamic(Palette.starting)
    static let meter = dynamic(Palette.meter)
    /// A stopped server, and players who are away.
    static let stopped = dynamic(Palette.stopped)
    // The basalt spine (K786): its ground, words, bead fills and outlines, badge pills, the lizard's tile and focus.
    static let spine = dynamic(Palette.side)
    static let spineInk = dynamic(Palette.sideInk)
    static let spineMuted = dynamic(Palette.sideMuted)
    static let beadIdle = dynamic(Palette.beadIdle)
    static let beadEdge = dynamic(Palette.beadEdge)
    static let beadOn = dynamic(Palette.beadOn)
    static let beadRing = dynamic(Palette.selMark)
    static let pill = dynamic(Palette.pill)
    static let onPill = dynamic(Palette.onPill)
    static let lizardTile = dynamic(Palette.sel)
    static let spineFocus = dynamic(Palette.sideFocus)
    static let info = dynamic(Palette.info)
    static let infoWash = dynamic(Palette.infoWash)
    /// Plugin source badge colours, by SourceKind raw value: (tint, icon accent).
    static let sourceColors: [String: (wash: Color, accent: Color)] = Dictionary(uniqueKeysWithValues:
        Palette.sources.map { ($0.name, (dynamic($0.wash), dynamic($0.accent))) })

    static let controlHeight: CGFloat = 32
    static let controlRadius: CGFloat = 8
    static let cardRadius: CGFloat = 10

    /// The palette's numbers live in GilaMonsterCore, where `gilamonster-check` holds every pair to WCAG AA.
    /// Bold or Quiet, read each time a color is drawn. Set by the Theme setting, which also redraws every window.
    nonisolated(unsafe) static var flavor: Palette.Flavor = ThemeChoice.load()

    private static func dynamic(_ swatch: Palette.Swatch) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let mode: Palette.Mode = switch match {
            case .accessibilityHighContrastAqua: .contrastLight
            case .accessibilityHighContrastDarkAqua: .contrastDark
            case .darkAqua: .dark
            default: .light
            }
            return nsColor(swatch.hex(mode, flavor))
        })
    }

    /// A palette color by the name ControlLook gives it, so the checks and the app agree on which color a part uses.
    static func named(_ name: String) -> Color { dynamic(Palette.named[name] ?? Palette.ink) }

    /// A fixed art color (the pixel lizard, the bead band, made-up faces). Decoration only, never text, and the same in
    /// every appearance, as the icon is.
    static func art(_ hex: UInt32) -> Color { Color(nsColor: nsColor(hex)) }

    /// Lilita One (SIL OFL 1.1, brand/fonts/lilitaone) for the one status sentence and player names. Falls back to the
    /// rounded system face if the font couldn't be loaded, so text is never lost.
    static func display(_ size: CGFloat) -> Font {
        BrandFonts.lilitaLoaded ? .custom(BrandFonts.lilita, size: size) : .system(size: size, weight: .bold, design: .rounded)
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
                .frame(minWidth: 24, minHeight: Theme.controlHeight)
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay {
                    // A disabled button has a dashed outline, so it is told apart by more than its color.
                    RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1, dash: enabled ? [] : [4, 3]))
                }
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: Theme.controlRadius + 2).strokeBorder(Theme.accent, lineWidth: 2).padding(-3)
                    }
                }
                // Disabled is drawn in its own colors (K801), each held to WCAG by the palette checks. Fading the
                // enabled button to half strength left the main button's label near 2:1.
                .opacity(enabled && configuration.isPressed ? 0.8 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
        }

        private var foreground: Color {
            guard enabled else { return Theme.named(ControlLook.disabledButton.label) }
            return switch kind {
            case .primary: Theme.onPop
            case .secondary: Theme.ink
            case .danger: Theme.danger
            }
        }
        private var fill: Color {
            guard enabled else { return Theme.named(ControlLook.disabledButton.fill) }
            return switch kind {
            case .primary: Theme.pop
            case .secondary: hovering && enabled ? Theme.raised : Theme.surface
            case .danger: hovering && enabled ? Theme.dangerWash : Theme.surface
            }
        }
        private var borderColor: Color {
            guard enabled else { return Theme.named(ControlLook.disabledButton.edge) }
            return switch kind {
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
    /// One line under the title saying what the card is, so it isn't repeated above a long list.
    var subtitle: String?
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
            if let subtitle { Text(subtitle).font(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
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
            Text(text).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.tail).help(text)
        } icon: {
            Image(systemName: icon ?? tone.icon).font(.body).foregroundStyle(tone.color)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tone.wash, in: Capsule())
    }
}

/// Where the column beside the spine and its banner row were drawn, for the debug snapshot's report (K815).
/// Present in release builds too, because the views name it in closures; only debug snapshots ever write it.
@MainActor enum SnapshotProbe {
    static var column = CGRect.null
    static var banners = CGRect.null
}

extension View {
    /// Debug snapshots only: records where this view was drawn in the window. Does nothing in the app.
    @ViewBuilder func snapshotProbe(_ record: @escaping @MainActor (CGRect) -> Void) -> some View {
        #if DEBUG
        if AppModel.isSnapshot {
            background(GeometryReader { area in
                let frame = area.frame(in: .global)
                Color.clear.onAppear { record(frame) }.onChange(of: frame) { record(frame) }
            })
        } else { self }
        #else
        self
        #endif
    }
}

/// A full-width message with an optional action.
struct Callout<Actions: View>: View {
    let tone: Tone
    let title: String
    var detail: String?
    /// Off when whoever shows it does the announcing, so nothing is said twice.
    var announces = true
    /// Read by VoiceOver as one element, title then detail, when there's nothing inside to press.
    var spokenAsOne = false
    @ViewBuilder var actions: Actions
    @State private var expanded = false

    var body: some View {
        // A long title (often a raw error) keeps one sentence; the rest joins the detail, which shows three lines
        // until Show Details (Overflow).
        let text = Overflow.callout(title: title, detail: detail)
        let long = Overflow.isLong(text.detail)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.icon).foregroundStyle(tone.color).font(.title3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(text.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = text.detail {
                    Text(detail).foregroundStyle(Theme.ink)
                        .lineLimit(long && !expanded ? Overflow.detailLines : nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if long {
                        Button(expanded ? "Hide Details" : "Show Details") { expanded.toggle() }
                            .buttonStyle(.disclosureLink(expanded ? "chevron.up" : "chevron.down")).font(.body)
                            .accessibilityHint(expanded ? "Shows only the first lines" : "Shows the whole message")
                    }
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.wash, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(tone.color, lineWidth: 1) }
        .accessibilityElement(children: spokenAsOne && !long ? .ignore : .contain)
        .accessibilityLabel(spokenAsOne && !long ? "\(tone.announcement.prefix): \(text.title). \(text.detail ?? "")" : "\(tone.announcement.prefix): \(text.title)")
        .onAppear { announce(text.title) }
        .onChange(of: title) { announce(Overflow.callout(title: title, detail: detail).title) }
    }

    private func announce(_ title: String) {
        guard announces else { return }
        let word = tone.announcement
        Announcer.say("\(word.prefix): \(title)", urgent: word.urgent)
    }
}

extension Callout where Actions == EmptyView {
    init(tone: Tone, title: String, detail: String? = nil, announces: Bool = true, spokenAsOne: Bool = false) {
        self.init(tone: tone, title: title, detail: detail, announces: announces, spokenAsOne: spokenAsOne) { EmptyView() }
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
        // Side by side when it fits (about 280 pt and up), stacked below that so a long value gets a whole line.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(Theme.ink).lineLimit(1).textSelection(.enabled)
            }
            .frame(minWidth: 280)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).foregroundStyle(Theme.muted)
                Text(value).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
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
                    Text(b.source).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.tail).help(b.source)
                } icon: {
                    Image(systemName: source.kind.symbol).font(.body).foregroundStyle(colors.accent)
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(colors.wash, in: Capsule())
                Text(b.id).font(.body.monospaced()).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
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

// MARK: - Switches

/// A switch GilaMonster draws itself (K801). The system switch was seen drawn half on, a teal track with the knob in the
/// middle, on the Lab's check rows. This one puts the knob at one end or the other, and when it's disabled it keeps
/// its end, turns gray with a dashed outline and shows a lock. It draws no label: give it an accessibility label.
/// VoiceOver reads it as a switch that is On or Off, with why it's locked when it is.
struct ThemedSwitchStyle: ToggleStyle {
    /// Said after On or Off when the switch is disabled.
    var lockedBecause = "locked"

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(Track(isOn: configuration.isOn, lockedBecause: lockedBecause))
    }

    private struct Track: ButtonStyle {
        let isOn: Bool
        let lockedBecause: String
        func makeBody(configuration: Configuration) -> some View { Drawn(isOn: isOn, lockedBecause: lockedBecause, pressed: configuration.isPressed) }
    }

    private struct Drawn: View {
        let isOn: Bool
        let lockedBecause: String
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let look = ControlLook.switchParts(on: isOn, enabled: enabled)
            Capsule().fill(Theme.named(look.track))
                .overlay { Capsule().strokeBorder(Theme.named(look.edge), style: StrokeStyle(lineWidth: 1, dash: enabled ? [] : [3, 2])) }
                .overlay(alignment: look.knobTrailing ? .leading : .trailing) {
                    if let lock = look.lock {
                        Image(systemName: "lock.fill").resizable().scaledToFit().frame(width: 9, height: 10).foregroundStyle(Theme.named(lock)).padding(.horizontal, 6).accessibilityHidden(true)
                    }
                }
                // Locked on has a filled gray track, so its dashes go inside, in the knob's color, which the checks hold on it.
                .overlay { if !enabled && isOn { Capsule().strokeBorder(Theme.named(look.knob), style: StrokeStyle(lineWidth: 1, dash: [3, 2])).padding(2) } }
                // A fixed size, so the alignment can move it: a bare Circle fills the track and sits in the middle.
                .overlay(alignment: look.knobTrailing ? .trailing : .leading) { Circle().fill(Theme.named(look.knob)).frame(width: 16, height: 16).padding(3) }
                .frame(width: 40, height: 22)
                .overlay { if focused { Capsule().strokeBorder(Theme.accent, lineWidth: 2).padding(-3) } }
                .opacity(pressed ? 0.8 : 1)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isOn)
                .accessibilityAddTraits(.isToggle)
                .accessibilityValue(ControlLook.switchValue(on: isOn, enabled: enabled, lockedBecause: lockedBecause))
        }
    }
}

extension ToggleStyle where Self == ThemedSwitchStyle {
    static var themedSwitch: ThemedSwitchStyle { ThemedSwitchStyle() }
    static func themedSwitch(lockedBecause: String) -> ThemedSwitchStyle { ThemedSwitchStyle(lockedBecause: lockedBecause) }
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

// MARK: - Long lists (Overflow)

/// "Show 12 More" under a cut-off list, and "Show Fewer" once it's open.
struct ShowMoreButton: View {
    let hidden: Int
    @Binding var expanded: Bool
    var body: some View {
        if expanded || hidden > 0 {
            Button(expanded ? "Show Fewer" : "Show \(hidden) More") { expanded.toggle() }
                .buttonStyle(.disclosureLink(expanded ? "chevron.up" : "chevron.down")).font(.body)
        }
    }
}

/// Several problems of one kind in one callout, as a list, cut off after `Overflow.Limit.warnings`.
struct ProblemList: View {
    let tone: Tone
    let what: String
    let problems: [String]
    @State private var expanded = false
    var body: some View {
        if problems.count == 1 {
            Callout(tone: tone, title: what, detail: problems[0])
        } else if !problems.isEmpty {
            let cut = Overflow.slice(problems, limit: Overflow.Limit.warnings, expanded: expanded)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tone.icon).foregroundStyle(tone.color).font(.title3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(what): \(problems.count) problems").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    ForEach(Array(cut.shown.enumerated()), id: \.offset) { _, problem in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(Theme.muted).accessibilityHidden(true)
                            Text(problem).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                    ShowMoreButton(hidden: cut.hidden, expanded: $expanded)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.wash, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(tone.color, lineWidth: 1) }
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// A name in a row: one line, the middle cut when it's too long, the whole name on hover.
    func rowName(_ full: String) -> some View {
        lineLimit(1).truncationMode(.middle).help(full).layoutPriority(1)
    }
}

/// A heading for a group of rows inside a page.
struct GroupHeading: View {
    let text: String
    var help: String?
    init(_ text: String, help: String? = nil) { self.text = text; self.help = help }
    var body: some View {
        Text(text).font(.headline).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            .help(help ?? "")
    }
}

extension View {
    /// A tooltip that VoiceOver and Voice Control users get too: the same words as the accessibility hint.
    func helped(_ text: String) -> some View {
        help(text).accessibilityHint(text)
    }
}

/// The title at the top of a sheet, announced as a heading.
struct SheetTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Puts the keyboard cursor in this field when its sheet opens, so typing can start at once.
struct FocusOnOpen: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).onAppear { focused = true }
    }
}

extension View {
    func focusOnOpen() -> some View { modifier(FocusOnOpen()) }
}

/// A text button that isn't told apart by color alone: underlined, with a small symbol after it. Its text is ink,
/// which is held to 4.5:1 on every surface and wash it sits on (PaletteChecks, "link buttons").
struct DisclosureLinkStyle: ButtonStyle {
    let symbol: String
    func makeBody(configuration: Configuration) -> some View { LinkBody(configuration: configuration, symbol: symbol) }
    private struct LinkBody: View {
        let configuration: Configuration
        let symbol: String
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            HStack(spacing: 4) {
                configuration.label.underline()
                Image(systemName: symbol).font(.body.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(Theme.ink)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.5)
        }
    }
}

extension ButtonStyle where Self == DisclosureLinkStyle {
    static func disclosureLink(_ symbol: String) -> DisclosureLinkStyle { DisclosureLinkStyle(symbol: symbol) }
}

/// A field with the control outline (3:1 on every surface) instead of the system's faint one. Give the field a prompt
/// styled `Theme.muted` with `ThemedPrompt` so the placeholder keeps its contrast too.
struct ThemedFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.controlBorder, lineWidth: 1) }
    }
}

extension TextFieldStyle where Self == ThemedFieldStyle {
    static var themed: ThemedFieldStyle { ThemedFieldStyle() }
}

/// A placeholder in the muted color (4.5:1 on the surfaces).
func ThemedPrompt(_ text: String) -> Text { Text(text).foregroundStyle(Theme.muted) }
