import AppKit
import LeafJuiceCore
import SwiftUI

/// Publishing builds to the web server's folder (D189). Each publish gets a new random address; the old one goes once
/// nobody who might still need it is online. Packmule reads the hash from the file name.
struct PackPublishCard: View {
    let server: ServerController
    let recipeNames: [String]
    @State private var settings = PackPublishSettings()
    @State private var problem: String?
    @State private var copied: String?
    @State private var telling: String?
    @State private var configNotes: [String: String] = [:]

    var body: some View {
        Card(title: "Publish to your web server", systemImage: "arrow.up.doc") {
            // Each build's status and its buttons come first, so Updated by Hand is in view without scrolling (2026-11-16).
            ForEach(recipeNames.filter { !ResourcePacks.history($0).isEmpty }, id: \.self) { name in recipeRow(name) }
            if let problem { Callout(tone: .danger, title: "Not published", detail: problem) }
            Divider()
            Hint("For a web server such as Caddy that serves a folder on this Mac. Each build goes in under a new random address, named by its SHA-1, so Packmule reads the hash from the link. Only the current build and one on its way out are ever there.")
            LabeledContent("Folder it serves") {
                HStack {
                    Text(settings.folder.isEmpty ? "Not chosen" : (settings.folder as NSString).abbreviatingWithTildeInPath).foregroundStyle(Juice.ink).lineLimit(1).truncationMode(.middle)
                    Button("Choose…", action: chooseFolder).buttonStyle(.juice)
                }
            }
            LabeledContent("Its web address") {
                TextField("https://join.example.test/packs/", text: $settings.baseURL).textFieldStyle(.roundedBorder)
                    .onSubmit(save).accessibilityLabel("Web address of that folder")
            }
            if let why = PackPublish.problem(settings) { Hint(why) }
            Hint("With Packmule 0.2.1 or later and Plugin commands on, LeafJuice tells Packmule each new link itself, and Packmule downloads and checks it before switching. Otherwise copy the link into Packmule's config.yml and run /packmule reload. LeafJuice reads config.yml (it never changes it) and marks the build in use once Packmule has it, or press Updated by Hand. The old build is kept until Packmule uses the new one.")
        }
        .onAppear(perform: readPackmuleConfig)
    }

    @ViewBuilder private func recipeRow(_ name: String) -> some View {
        let key = ResourcePacks.slug(name)
        let builds = settings.builds[key] ?? []
        let newest = ResourcePacks.history(name).first
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.body.weight(.semibold)).foregroundStyle(Juice.ink)
            LabeledContent("Pack name in Packmule") {
                TextField("main", text: Binding(get: { settings.packmuleNames?[key] ?? "" }, set: { value in
                    var names = settings.packmuleNames ?? [:]
                    names[key] = value.trimmingCharacters(in: .whitespaces)
                    settings.packmuleNames = names
                }))
                .textFieldStyle(.roundedBorder).onSubmit(save).accessibilityLabel("Packmule pack name for \(name)")
            }
            if let current = builds.first {
                HStack {
                    Text(current.url).font(.callout.monospaced()).foregroundStyle(Juice.ink).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button(copied == current.url ? "Copied" : "Copy Link") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(current.url, forType: .string); copied = current.url
                    }
                    .buttonStyle(.juice).accessibilityLabel("Copy the link for \(name)")
                }
                Hint("Published \(current.publishedAt.formatted(.relative(presentation: .named))). SHA-1 \(current.sha1).")
                if current.handedOff == true {
                    Label(current.handOffNote ?? "Packmule uses this link.", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Juice.ink)
                } else {
                    if let waiting = configNotes[key] {
                        Callout(tone: .info, title: "Waiting for Packmule to load its config", detail: waiting)
                    } else if let note = current.handOffNote {
                        Callout(tone: .warning, title: "Packmule doesn't use this link yet", detail: note)
                    }
                    HStack {
                        Button(telling == key ? "Telling Packmule…" : "Send to Packmule") { send(name) }.buttonStyle(.juice).disabled(telling != nil)
                            .accessibilityLabel("Send the new link for \(name) to Packmule")
                        Button("Check config.yml Again") { readPackmuleConfig() }.buttonStyle(.juice)
                            .accessibilityLabel("Check Packmule's config.yml again for \(name)")
                        Button("Updated by Hand") { server.markHandedOff(recipe: name); settings = server.packPublishSettings }.buttonStyle(.juice)
                            .accessibilityLabel("Mark Packmule as updated by hand for \(name)")
                    }
                }
                if builds.count > 1 { Hint("\(builds.count - 1) older build\(builds.count == 2 ? " is" : "s are") still there, and go once everyone online at the switch has left (at least \(PackPublish.graceMinutes) minutes).") }
            } else {
                Hint("Not published yet.")
            }
            if let newest, newest.sha1 != builds.first?.sha1 {
                Button("Publish the Newest Build") { publish(name, newest.sha1) }
                    .buttonStyle(.juicePrimary).disabled(PackPublish.problem(settings) != nil)
                    .accessibilityLabel("Publish the newest build of \(name)")
            }
        }
        .padding(.vertical, 4)
    }

    /// Reads Packmule's config.yml for each recipe (read only) and picks up any build it already gives players.
    private func readPackmuleConfig() {
        var notes: [String: String] = [:]
        for name in recipeNames { if let note = server.checkPackmuleConfig(recipe: name) { notes[ResourcePacks.slug(name)] = note } }
        configNotes = notes
        settings = server.packPublishSettings
    }

    private func save() {
        var s = server.packPublishSettings
        s.folder = settings.folder; s.baseURL = settings.baseURL; s.packmuleNames = settings.packmuleNames
        server.packPublishSettings = s; settings = s
    }

    private func send(_ name: String) {
        save()
        telling = ResourcePacks.slug(name)
        Task {
            await server.tellPackmule(recipe: name)
            telling = nil
            settings = server.packPublishSettings
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.folder = url.path
        save()
    }

    private func publish(_ name: String, _ sha1: String) {
        save()
        do { try server.publishPack(recipe: name, sha1: sha1); problem = nil } catch { problem = error.localizedDescription; return }
        settings = server.packPublishSettings
        if settings.packmuleNames?[ResourcePacks.slug(name)]?.isEmpty == false { send(name) }
    }
}
