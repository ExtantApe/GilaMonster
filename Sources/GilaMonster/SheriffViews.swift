import GilaMonsterCore
import SwiftUI

/// Choose someone's profiles and approve them, through Sheriff. Sheriff's questions appear here, and each needs a tick.
struct SheriffApproval: View {
    let server: ServerController
    let uuid: String
    let name: String
    let profiles: [SheriffProfile]
    /// Called after Sheriff confirms a change.
    var done: (String) -> Void = { _ in }
    @State private var current: SheriffPlayer?
    @State private var reading = true
    @State private var chosen = Set<String>()
    @State private var questions: [ConfirmQuestion] = []
    @State private var answered = Set<String>()
    @State private var problem: String?
    @State private var result: String?
    @State private var working = false

    private var before: Set<String> { Set(current?.profiles ?? []) }
    private var adding: [String] { chosen.subtracting(before).sorted() }
    private var removing: [String] { before.subtracting(chosen).sorted() }
    private var nothingToDo: Bool { adding.isEmpty && removing.isEmpty && (current?.whitelisted ?? false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if reading {
                Hint("Asking Sheriff what \(name) has…")
            } else {
                if let current {
                    Fact(label: "On the allowlist", value: current.whitelisted ? "Yes" : "Not yet")
                    if !current.throughOtherGroups.isEmpty {
                        Hint("Also gets \(labels(current.throughOtherGroups)) through another group, which Sheriff can't change here.")
                    }
                }
                ProfileChoiceCard(profiles: profiles, chosen: $chosen, empty: "Sheriff has no profiles set up. Approving gives lobby-only access until an admin adds some.", showDetail: true) {
                    questions = []; answered = []; result = nil
                }
                QuestionsCard(questions: questions, answered: $answered, intro: "Nothing has changed yet. Tick each one to go ahead.")
                if let problem { Callout(tone: .danger, title: problem) }
                if let result { Callout(tone: .good, title: result) }
                HStack {
                    Button(working ? "Working…" : buttonTitle, action: apply)
                        .buttonStyle(.themedPrimary)
                        .disabled(working || current == nil || nothingToDo || questions.contains { !answered.contains($0.id) })
                    Hint("Goes through Sheriff, with its own checks, and is logged in Sheriff's change log.")
                }
            }
        }
        .task(id: uuid) { await read() }
    }

    private var buttonTitle: String {
        if !questions.isEmpty { return "Go Ahead" }
        if current?.whitelisted == false { return "Approve \(name)" }
        return "Save Profiles"
    }

    private func labels(_ ids: [String]) -> String {
        ids.map { id in profiles.first { $0.id == id }?.label ?? id }.joined(separator: ", ")
    }

    private func read() async {
        reading = true
        problem = nil
        switch await server.sheriffShow(uuid: uuid) {
        case .success(let p):
            current = p
            chosen = Set(p.profiles)
        case .failure(let e):
            current = nil
            problem = e.message
        }
        reading = false
    }

    private func apply() {
        working = true
        problem = nil
        result = nil
        let yes = questions.map(\.id)
        Task {
            defer { working = false }
            switch await server.sheriffApply(uuid: uuid, name: name, add: adding, remove: removing, yes: yes) {
            case .done(let message):
                questions = []; answered = []
                result = message
                await read()
                done(message)
            case .questions(let qs):
                questions = qs; answered = []
            case .failed(let why):
                problem = why
            case .notConfirmed:
                problem = "Sheriff didn't answer in 15 seconds. The change may still have happened, so this shows what Sheriff has now."
                await read()
            }
        }
    }
}

/// Sheriff's profiles as a card of ticks, six showing and the rest behind Show More.
struct ProfileChoiceCard: View {
    let profiles: [SheriffProfile]
    @Binding var chosen: Set<String>
    let empty: String
    var showDetail = false
    var changed: () -> Void = {}
    @State private var expanded = false

    static func detail(_ p: SheriffProfile) -> String {
        var parts: [String] = []
        if !p.worlds.isEmpty { parts.append("Worlds: \(p.worlds.joined(separator: ", "))") }
        if let circle = p.circle { parts.append("Chat circle: \(circle)") }
        if let first = p.description.first { parts.append(first) }
        return parts.isEmpty ? "No worlds or circle of its own." : parts.joined(separator: ". ")
    }

    var body: some View {
        let cut = Overflow.slice(profiles, limit: Overflow.Limit.profiles, expanded: expanded)
        let hiddenTicked = profiles.dropFirst(cut.shown.count).filter { chosen.contains($0.id) }.count
        VStack(alignment: .leading, spacing: 6) {
            HeadingText(profiles.isEmpty ? "Profiles" : "Profiles (\(profiles.count))").foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if profiles.isEmpty { Hint(empty) }
            ForEach(cut.shown) { profile in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(profile.label, isOn: Binding(get: { chosen.contains(profile.id) }, set: { on in
                        if on { chosen.insert(profile.id) } else { chosen.remove(profile.id) }
                        changed()
                    }))
                    .toggleStyle(.checkbox)
                    .accessibilityHint(Self.detail(profile))
                    if showDetail { Hint(Self.detail(profile)).padding(.leading, 20) }
                }
            }
            ShowMoreButton(hidden: cut.hidden, expanded: $expanded)
            if hiddenTicked > 0 { Hint("\(hiddenTicked) more ticked below.") }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .contain)
    }
}

/// Sheriff's questions, one tick each, in a card of their own. Nothing shows when there are none.
struct QuestionsCard: View {
    let questions: [ConfirmQuestion]
    @Binding var answered: Set<String>
    let intro: String
    @State private var expanded = false

    var body: some View {
        if !questions.isEmpty {
            let cut = Overflow.slice(questions, limit: Overflow.Limit.profiles, expanded: expanded)
            VStack(alignment: .leading, spacing: 6) {
                Label { HeadingText("Sheriff asks first (\(questions.count))") } icon: { Image(systemName: Tone.warning.icon) }
                    .foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Hint(intro)
                ForEach(cut.shown, id: \.id) { q in
                    Toggle(q.question, isOn: Binding(get: { answered.contains(q.id) }, set: { on in
                        if on { answered.insert(q.id) } else { answered.remove(q.id) }
                    }))
                    .toggleStyle(.checkbox)
                }
                ShowMoreButton(hidden: cut.hidden, expanded: $expanded)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tone.warning.wash, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Tone.warning.color, lineWidth: 1) }
            .accessibilityElement(children: .contain)
        }
    }
}

/// The same, in a sheet, for someone already on the list.
struct SheriffProfileSheet: View {
    let server: ServerController
    let entry: AllowlistEntry
    let profiles: [SheriffProfile]
    let changed: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetTitle("Profiles for \(entry.name)")
            SheriffApproval(server: server, uuid: entry.uuid, name: entry.name, profiles: profiles) { _ in changed() }
            if server.hasWelcomeWagon { Divider(); WebSignInSection(server: server, name: entry.name) }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: Theme.sheet(500))
    }
}
