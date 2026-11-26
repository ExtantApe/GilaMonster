import AppKit
import GilaMonsterCore
import SwiftUI

/// The Lab page (Head of Design review, 2026-11-16): what the lab is, the checks to run with one Run Checks button,
/// keeping a copy, and saved copies. The lab itself is built for each run and deleted when it ends (D229).
struct LabPage: View {
    let model: AppModel
    let server: ServerController
    @State private var note = ""
    @State private var confirmDelete: LabSave?
    @State private var versions: [String] = []
    @State private var chosen = ""
    @State private var skipped: [String] = []
    @AppStorage("labChecks") private var checksText = "plugins,upgrade,fresh"

    private var lab: LabController { model.lab }
    private var included: Set<LabStation> { Set(checksText.split(separator: ",").compactMap { LabStation(rawValue: String($0)) }) }

    var body: some View {
        Page(title: "Lab", subtitle: "Tests \(server.profile.name)'s plugins and rehearses its upgrades on a practice server.") {
            if server.isLab {
                LabRunCard(model: model)
            } else {
                Card(title: "Checks", systemImage: "flask") {
                    Text("Each run builds a practice server, the Lab, with its own worlds and bot players, listening only on this Mac. It's deleted when the run ends, pass or fail. The results and the report stay.")
                        .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Upgrade to").foregroundStyle(Theme.muted)
                        Picker("Version to upgrade to", selection: $chosen) {
                            Text("Choose…").tag("")
                            ForEach(versions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(maxWidth: 200).disabled(lab.isBusy)
                        .onChange(of: chosen) { _, version in pick(version) }
                        if let target = lab.target { Hint("\(target.flavor.title) \(target.label)") }
                        Spacer()
                        Text("Now \(server.profile.software.label)").foregroundStyle(Theme.muted)
                    }
                    Text("Checks to run").font(.body.weight(.semibold)).foregroundStyle(Theme.ink).padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(LabStation.allCases) { station in
                        LabStationRow(station: station, lab: lab, server: server, included: Binding(get: { included.contains(station) }, set: { on in
                            var set = included
                            if on { set.insert(station) } else { set.remove(station) }
                            checksText = LabStation.allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
                        }))
                        if station != LabStation.allCases.last { Divider() }
                    }
                    LabProgress(lab: lab)
                    ForEach(skipped, id: \.self) { Hint($0) }
                    HStack {
                        Button("Run Checks") { runChecks() }
                            .buttonStyle(.themedPrimary)
                            .disabled(lab.isBusy || included.isEmpty)
                            .helped(lab.isBusy ? "A run is going now." : included.isEmpty ? "Tick at least one check first." : "Runs the ticked checks in order.")
                        Spacer()
                    }
                    keepRow
                    if let report = lab.report, lab.result(.fresh) != nil { RehearsalVerdict(report: report, model: model, server: server) }
                }
                if !lab.saves.isEmpty { savesCard }
            }
        }
        .onAppear { if !server.isLab, !lab.isBusy { lab.chooseModel(server) } }
        .task(id: server.id) { await loadVersions() }
        .confirmationDialog("Delete this saved copy?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) { if let save = confirmDelete { try? lab.deleteSave(save) } }
        } message: {
            Text(confirmDelete?.fileName ?? "")
        }
    }

    /// A choice for the next run, or, during a run, for this one.
    @ViewBuilder private var keepRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if lab.isBusy, lab.keepRequest == nil {
                Button("Keep This Lab") { lab.keepCopy(note: note) }.buttonStyle(.themed)
                    .helped("Saves a copy of this run's lab just before it's deleted.")
            } else {
                Toggle(lab.isBusy ? "Keep a copy of this Lab when the run ends" : "Keep a copy of the Lab after the next run", isOn: Binding(
                    get: { lab.keepRequest != nil },
                    set: { on in if on { lab.keepCopy(note: note) } else { lab.dontKeepCopy() } }
                ))
                .toggleStyle(.checkbox).foregroundStyle(Theme.ink)
            }
            if lab.keepRequest != nil {
                HStack {
                    Text("Note").foregroundStyle(Theme.muted)
                    TextField("Note", text: $note, prompt: Text("Such as before the 26 upgrade"))
                        .labelsHidden().textFieldStyle(.plain).padding(.horizontal, 6).padding(.vertical, 4)
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.controlBorder, lineWidth: 1) }
                        .frame(maxWidth: 320).accessibilityLabel("Note for the kept copy")
                        .onChange(of: note) { _, text in lab.keepCopy(note: text) }
                }
                Hint("The copy goes in Saved copies below. Nothing else is kept.")
            }
        }
    }

    private var savesCard: some View {
        Card(title: "Saved copies", systemImage: "archivebox") {
            ForEach(lab.saves) { save in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(save.note.isEmpty ? save.software : save.note).foregroundStyle(Theme.ink)
                        Hint("\(save.date.formatted(date: .abbreviated, time: .shortened)), \(save.software), \(Format.bytes(save.size))")
                    }
                    Spacer()
                    Button("Delete…") { confirmDelete = save }.buttonStyle(.themed).disabled(lab.isBusy)
                        .accessibilityLabel("Delete \(save.note.isEmpty ? save.software : save.note)")
                }
            }
            Button("Show Saved Copies in Finder") { NSWorkspace.shared.open(LabFiles.saves) }.buttonStyle(.themed)
        }
    }

    private func runChecks() {
        skipped = []
        let chosen = included
        model.withLab { [lab, server] in
            Task {
                let left = await lab.runChecks(chosen, model: server)
                skipped = left.map { "\($0.0.title) didn't run: \($0.1.prefix(1).lowercased() + $0.1.dropFirst())." }
            }
        }
    }

    private func loadVersions() async {
        guard server.profile.software.flavor.canDownload else { return }
        let all = (try? await SoftwareCatalog.versions(server.profile.software.flavor)) ?? []
        let now = server.profile.software.gameVersion
        versions = all.filter { version in
            guard let v = GameVersion(version), v.isStableRelease else { return false }
            return now.map { v >= $0 } ?? true
        }
        chosen = lab.target?.mcVersion ?? ""
    }

    private func pick(_ version: String) {
        guard !version.isEmpty, version != lab.target?.mcVersion else { return }
        Task {
            if let build = try? await SoftwareCatalog.latestBuild(server.profile.software.flavor, mc: version, channels: server.profile.software.channels) {
                lab.chooseTarget(build)
            }
        }
    }
}

/// On the lab's own Overview while a run has it: what it is, and how the run is going.
struct LabRunCard: View {
    let model: AppModel

    var body: some View {
        Card(title: "This lab is for one run", systemImage: "flask") {
            Text("A Lab run built it for the checks going now, and deletes it when the run ends. The results stay on the Lab page of the server it's modeled on.")
                .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            LabProgress(lab: model.lab)
            if let real = model.lab.model(from: model.servers) {
                Button("Open the Lab") { model.openLabBoard() }.buttonStyle(.themed)
                    .accessibilityHint("\(real.profile.name)'s Lab page")
            }
        }
    }
}

struct LabProgress: View {
    let lab: LabController

    var body: some View {
        if let step = lab.step {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                Text(step).foregroundStyle(Theme.ink)
            }
        }
        if let failure = lab.failure {
            Callout(tone: .danger, title: "The lab couldn't finish that", detail: failure)
        }
    }
}

/// One check: whether it's in the next run, what it does, its light, and its details behind a chevron.
struct LabStationRow: View {
    let station: LabStation
    let lab: LabController
    let server: ServerController
    @Binding var included: Bool
    @State private var open = false

    private var light: StationLight { lab.light(station, model: server) }
    private var result: StationResult? { lab.result(station) }
    private var hasDetails: Bool { result.map { !$0.checks.isEmpty || !$0.groups.isEmpty } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Toggle(station.title, isOn: $included)
                    .toggleStyle(.switch).labelsHidden().disabled(lab.isBusy)
                    // An off switch is a white knob on a pale track; the control outline gives it a 3:1 edge.
                    .overlay { if !included { Capsule().strokeBorder(Theme.controlBorder, lineWidth: 1).allowsHitTesting(false).accessibilityHidden(true) } }
                    .accessibilityLabel("Include \(station.title) in the next run")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(station.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                        if station.isOptional { Text("Optional").font(.body).foregroundStyle(Theme.muted) }
                    }
                    Hint(detailLine)
                    if case .failed = light, let next = nextStep { Text(next).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true) }
                    if light == .running, let step = lab.step { Text(step).font(.body).foregroundStyle(Theme.ink) }
                }
                Spacer(minLength: 8)
                StatusLight(light: light)
                Button { open.toggle() } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(Theme.muted)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain).opacity(hasDetails ? 1 : 0).disabled(!hasDetails)
                .accessibilityLabel("Details for \(station.title)").accessibilityValue(open ? "Shown" : "Hidden")
                .accessibilityHidden(!hasDetails)
            }
            if case .failed(acknowledged: false) = light, !station.isOptional {
                Button("Continue Anyway") { lab.continueAnyway(station) }.buttonStyle(.themed)
                    .helped("Unlocks the next check. This light stays red.")
            }
            if open, let result, hasDetails {
                StationDetails(result: result).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 52)
            }
        }
    }

    private var detailLine: String {
        switch light {
        case let .locked(reason): reason
        case .stale: "Your plugins or version changed since this ran. Run it again for a current answer."
        case .passed, .failed: result?.note.isEmpty == false ? result!.note : station.summary
        case .ready, .running: station.summary
        }
    }

    /// What failed first, and what to do about it.
    private var nextStep: String? {
        guard let result else { return nil }
        let first = result.checks.first { $0.outcome == .failed }?.title
            ?? result.groups.first { $0.outcome != .passed }.map { "\($0.title): \($0.plugins.prefix(3).joined(separator: ", "))" }
        let what: String = switch station {
        case .plugins: "Update or remove that plugin, then run again."
        case .settings: "Fresh settings passed, so one of your plugin settings is the cause. Check that plugin's config, then run again."
        case .upgrade: "Moving your data to the new version broke this. Wait for the plugin's update before upgrading, or Continue Anyway to see the fresh install."
        case .fresh: "The new version fails even from nothing, so a plugin isn't ready for it yet. Wait for its update."
        case .freshSettings: "The new version works with fresh settings, so change that plugin's settings before upgrading."
        }
        return first.map { "Failed first: \($0). \(what)" } ?? what
    }
}

/// The word and shape carry the meaning too, so it never relies on color alone.
struct StatusLight: View {
    let light: StationLight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if light == .running {
                ProgressView().controlSize(.small).accessibilityHidden(true)
            } else {
                Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
            }
            Text(word).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
        }
        .frame(minWidth: 96, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }

    private var word: String {
        switch light {
        case .locked: "Locked"
        case .ready: "Ready"
        case .running: "Running"
        case .passed: "Passed"
        case .failed(acknowledged: true): "Failed, continued"
        case .failed: "Failed"
        case .stale: "Out of date"
        }
    }

    private var icon: String {
        switch light {
        case .locked: "lock.fill"
        case .ready: "circle"
        case .running: "circle.dotted"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .stale: "clock.arrow.circlepath"
        }
    }

    private var color: Color {
        switch light {
        case .locked, .ready: Theme.muted
        case .running: Tone.info.color
        case .passed: Tone.good.color
        case .failed: Tone.danger.color
        case .stale: Tone.warning.color
        }
    }
}

struct StationDetails: View {
    let result: StationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CheckList(checks: result.checks)
            ForEach(result.groups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(group.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                        Badge(text: title(group.outcome), tone: tone(group.outcome))
                    }
                    Hint(group.plugins.joined(separator: ", "))
                    CheckList(checks: (group.fresh + (group.withSettings ?? [])).filter { $0.outcome != .passed })
                    ForEach(group.notes, id: \.self) { Hint($0) }
                }
            }
            ForEach(result.leftOut, id: \.self) { Hint($0) }
        }
    }

    private func title(_ outcome: MirrorBatch.Outcome) -> String {
        switch outcome {
        case .passed: "Passed"
        case .pluginProblem: "Plugin problem"
        case .settingsProblem: "Settings problem"
        }
    }

    private func tone(_ outcome: MirrorBatch.Outcome) -> Tone {
        switch outcome {
        case .passed: .good
        case .pluginProblem: .danger
        case .settingsProblem: .warning
        }
    }
}

struct CheckList: View {
    let checks: [LabCheck]

    var body: some View {
        ForEach(checks) { check in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon(check.outcome)).foregroundStyle(color(check.outcome)).accessibilityLabel(check.outcome.rawValue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.title).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if !check.detail.isEmpty { Hint(check.detail) }
                }
            }
        }
    }

    private func icon(_ outcome: LabCheck.Outcome) -> String {
        switch outcome {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "minus.circle"
        }
    }

    private func color(_ outcome: LabCheck.Outcome) -> Color {
        switch outcome {
        case .passed: Tone.good.color
        case .failed: Tone.danger.color
        case .skipped: Theme.muted
        }
    }
}

/// The last row of the board: what the two paths together suggest.
struct RehearsalVerdict: View {
    let report: RehearsalReport
    let model: AppModel
    let server: ServerController

    private var good: Bool { report.verdict == .bothPassed && !report.settingsProblem }

    var body: some View {
        Divider()
        Callout(tone: good ? .good : .warning, title: report.headline, detail: report.explanation) {
            Button("Open \(server.profile.name)'s Software") {
                model.selectedID = server.id
                model.page = .software
            }
            .buttonStyle(good ? .themedPrimary : .themed)
        }
        DisclosureGroup("What this didn't check") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(RehearsalReport.notChecked, id: \.self) { Text($0).foregroundStyle(Theme.ink) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.ink)
    }
}

/// Explains the Lab and takes the EULA acceptance it needs. Never ticked on anyone's behalf.
struct LabSetupSheet: View {
    let model: AppModel
    /// What to do once accepted.
    let then: @MainActor () -> Void
    @State private var accepted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Set up the Lab", systemImage: "flask").font(.title2.weight(.semibold)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Text("The Lab is a practice server in \((LabFiles.root.path as NSString).abbreviatingWithTildeInPath). GilaMonster fills it with its own worlds and bot players, and uses it to rehearse upgrades. It never copies your real worlds or players.")
                .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text("Running it means running a Minecraft server, so Mojang's EULA applies. Your acceptance covers the Lab and its rebuilds.")
                .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Link("Read the Minecraft EULA", destination: EULA.url)
            Toggle("I accept the Minecraft EULA", isOn: $accepted).toggleStyle(.checkbox).foregroundStyle(Theme.ink)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction)
                Button("Continue") {
                    model.lab.acceptEULA()
                    dismiss()
                    then()
                }
                .buttonStyle(.themedPrimary).disabled(!accepted).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
