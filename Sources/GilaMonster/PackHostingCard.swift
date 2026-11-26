import AppKit
import UniformTypeIdentifiers
import GilaMonsterCore
import SwiftUI

/// Each recipe's own address and hash, and the small web server behind them.
struct PackHostingCard: View {
    let server: ServerController
    let recipeNames: [String]
    let live: ResourcePacks.ServerPack
    let changed: () -> Void

    @State private var address = ""
    @State private var port = 8766
    @State private var error: String?
    @State private var results: [String: PackURLCheck] = [:]
    @State private var checking: String?
    @State private var replacing: String?
    @State private var elsewhere: String?
    @State private var elsewhereText = ""
    @State private var refresh = 0

    private var settings: PackHostSettings { server.packHostSettings }
    private var built: [String] { _ = refresh; return recipeNames.filter { !ResourcePacks.history($0).isEmpty } + ResourcePacks.exactNames() }

    var body: some View {
        Card(title: "Hosting", systemImage: "antenna.radiowaves.left.and.right") {
            if let error { Callout(tone: .danger, title: error) }
            if let problem = server.packHostError { Callout(tone: .danger, title: "Serving stopped", detail: problem) }
            if let plugin = server.perWorldPackPlugin {
                Callout(tone: .info, title: "\(plugin) is on this server", detail: "It sends the pack for each world, so GilaMonster won't change this server's pack settings. Give it each build's own address and SHA-1 from here. That address only ever gives that build, so the two can't fall out of step.")
                if live.isSet { Callout(tone: .warning, title: "server.properties still sets a pack", detail: "With \(plugin) sending the packs, this should usually be empty. Clear it on the Configs page if \(plugin) is meant to send every pack.") }
            }
            serving
            HStack {
                Button("Add an Exact Pack…") { addExact(to: nil) }.buttonStyle(.themed)
                Hint("Serves a zip exactly as it is, such as BlueMapMini's pack in plugins/BlueMapMini/pack, so its SHA-1 doesn't change.")
            }
            if built.isEmpty {
                Hint("Build a recipe, and its address shows here.")
            } else {
                ForEach(built, id: \.self) { name in
                    Divider()
                    row(name)
                }
            }
        }
        .id(refresh)
        .onAppear {
            address = settings.address
            port = settings.port
        }
        .confirmationDialog("Replace this address?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
            Button("Replace", role: .destructive) {
                if let name = replacing { server.newPackPath(recipe: name) }
                results = [:]
                reload()
            }
        } message: {
            Text("The old address stops working straight away. Anything using it, including this server or Packmule, needs the new one, or players can't load the pack.")
        }
    }

    private var serving: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Address", text: $address, prompt: Text("https://packs.example.net"))
                    .accessibilityLabel("Address players reach this Mac at")
                TextField("Port", value: $port, format: .number.grouping(.never)).frame(width: 70).accessibilityLabel("Port on this Mac")
                if server.packHostIsListening {
                    Badge(text: "Serving", tone: .good)
                    Button("Save") { saveAddress() }.buttonStyle(.themed)
                    Button("Stop") {
                        server.stopPackHost()
                        reload()
                    }
                    .buttonStyle(.themed)
                } else {
                    Button("Start Serving") { start() }.buttonStyle(.themedPrimary)
                }
            }
            if PackHosting.isOnlyThisMac(settings.address) { Hint("This address only works on this Mac, so it's good for testing and no use to players.") }
            Hint("GilaMonster listens on this Mac only, so something like Caddy has to carry it through your tunnel: a whole hostname, or one folder of one, such as https://join.example.net/zz. GilaMonster accepts requests with that folder or without it.")
            Toggle(isOn: Binding(get: { settings.joiningOnly }, set: { on in
                do { try server.setPackJoiningOnly(on); error = nil } catch { self.error = error.localizedDescription }
                reload()
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Only players joining this server").foregroundStyle(Theme.ink)
                    Text("A pack goes only to a game that names a player on the allowlist the server shows connecting in the last 5 minutes, or online now. Anyone else, a browser included, is told there's nothing there.")
                        .font(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if settings.joiningOnly, let tokenPath = server.packCheckTokenPath {
                LabeledContent("Packmule's token file") {
                    HStack {
                        Text((tokenPath as NSString).abbreviatingWithTildeInPath).font(.body.monospaced()).foregroundStyle(Theme.ink)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(tokenPath, forType: .string) }
                            .buttonStyle(.themed).accessibilityLabel("Copy the path of Packmule's token file")
                    }
                }
                Hint("Packmule's own link check sends this file's token straight to this Mac, so it gets past the joining check. It never works through a web server. To make a new one, delete the file and start serving again.")
            }
            if settings.joiningOnly {
                Hint("This stops casual downloads and shared links. A game's request can be faked, so someone who knows the name and ID of a player on the allowlist could still get the pack while that player is joining. Only players listed in the whitelist get it, whether or not the whitelist is switched on.")
            }
            Hint("The game can't sign in, so a long random path hides a pack, and every player's game is given it. It runs only while GilaMonster is open, uses your upload speed, and keeps no record of who downloads.")
        }
    }

    private func row(_ name: String) -> some View {
        let isElsewhere = settings.recipes[ResourcePacks.slug(name)]?.elsewhere != nil
        let newest = ResourcePacks.history(name).first?.sha1
        let exact = ResourcePacks.isExact(name)
        let perWorld = (server.hasPerWorldPacks || exact) && !isElsewhere
        let sha1 = isElsewhere || perWorld ? newest : server.servedPackSHA1(recipe: name)
        let url = perWorld ? newest.flatMap { server.packBuildAddress(recipe: name, sha1: $0) } : server.packAddress(recipe: name)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                if isElsewhere { Badge(text: "Hosted elsewhere", tone: .info) }
                if exact { Badge(text: "Exact file", tone: .info) }
                Spacer()
                if exact { Button("Add New Version…") { addExact(to: name) }.buttonStyle(.themed) }
            }
            if exact, !isElsewhere {
                if let template = server.packAddressTemplate(recipe: name) {
                    HStack {
                        Fact(label: "Address with {sha1}", value: template)
                        Button("Copy") { copy(template) }.buttonStyle(.themed).accessibilityLabel("Copy the address with {sha1}")
                    }
                }
                Callout(tone: .warning, title: "Players can't get this pack while GilaMonster is closed", detail: "If it's required, they can't join without it. Keep GilaMonster open whenever the server is running.")
                Hint("Each version keeps its own address. New Address changes all of them, so a plugin's public-url breaks until you paste the new one in.")
                ForEach(ResourcePacks.history(name).first?.warnings ?? [], id: \.self) { Hint($0) }
            }
            Fact(label: perWorld ? "Newest build's address" : "Address", value: url ?? "Enter an address above")
            Fact(label: "SHA-1", value: sha1 ?? (isElsewhere ? "Build it first" : "Nothing served yet"))
            if let result = results[name] { Callout(tone: result.ok ? .good : .danger, title: result.summary) }
            HStack {
                Button("Copy Address") { copy(url) }.buttonStyle(.themed).disabled(url == nil)
                Button("Copy SHA-1") { copy(sha1) }.buttonStyle(.themed).disabled(sha1 == nil)
                Button(checking == name ? "Checking…" : "Check") { check(name, url: url, sha1: sha1) }
                    .buttonStyle(.themed).disabled(url == nil || sha1 == nil || checking != nil)
                    .helped("Downloads it from the address, as a player's game would, and compares its SHA-1.")
                Button("Host Elsewhere…") {
                    elsewhereText = settings.recipes[ResourcePacks.slug(name)]?.elsewhere ?? ""
                    elsewhere = name
                }
                .buttonStyle(.themed)
                if !isElsewhere {
                    Button("New Address…") { replacing = name }.buttonStyle(.themed).accessibilityLabel("Replace the address for \(name)")
                }
            }
            if elsewhere == name {
                HStack {
                    TextField("Full address", text: $elsewhereText, prompt: Text("https://download.mc-packs.net/pack/….zip"))
                        .accessibilityLabel("Full address of this pack on another host")
                    Button("Save") {
                        do {
                            try server.setPackElsewhere(elsewhereText, recipe: name)
                            elsewhere = nil
                            results[name] = nil
                            reload()
                        } catch { self.error = error.localizedDescription }
                    }
                    .buttonStyle(.themed)
                    Button("Cancel") { elsewhere = nil }.buttonStyle(.themed)
                }
                Hint("Leave it empty to serve it from here again.")
            }
        }
    }

    private func addExact(to existing: String?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.prompt = existing == nil ? "Add" : "Add Version"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        let name = existing ?? file.deletingPathExtension().lastPathComponent
        Task {
            do {
                try await ResourcePacks.addExact(file, name: name)
                error = nil
                reload()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func reload() {
        refresh += 1
        changed()
    }

    private func saveAddress() {
        do {
            let restart = server.packHostIsListening && port != settings.port
            try server.setPackHost(address: address, port: port)
            address = settings.address
            if restart { try server.startPackHost() }
            error = nil
            reload()
        } catch { self.error = error.localizedDescription }
    }

    private func start() {
        do {
            try server.setPackHost(address: address, port: port)
            address = settings.address
            try server.startPackHost()
            error = nil
            Task {
                // The listener takes a moment to come up, or to report that the port is taken.
                try? await Task.sleep(for: .milliseconds(400))
                reload()
            }
        } catch { self.error = error.localizedDescription }
    }

    private func check(_ name: String, url: String?, sha1: String?) {
        guard let url, let sha1 else { return }
        checking = name
        Task {
            results[name] = await PackHosting.check(url: url, expected: sha1, ticket: server.packCheckTicket(for: url))
            checking = nil
        }
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
