import AppKit
import GilaMonsterCore
import SwiftUI

struct ConsolePage: View {
    let server: ServerController
    @State private var filter = ""
    @State private var minimumLevel: LogLevel = .debug
    @State private var follow = true
    @State private var command = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @FocusState private var commandFocused: Bool
    @AppStorage(TextZoom.key, store: AppDefaults.store) private var textSize = TextZoom.standard

    var body: some View {
        VStack(spacing: 0) {
            FlowRow(spacing: 10) {
                TextField("Filter", text: $filter, prompt: ThemedPrompt("Filter lines"))
                    .textFieldStyle(.themed).frame(width: 200, height: Theme.controlHeight)
                Picker("Show", selection: $minimumLevel) {
                    Text("All").tag(LogLevel.debug)
                    Text("Warnings").tag(LogLevel.warn)
                    Text("Errors").tag(LogLevel.error)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210, height: Theme.controlHeight)
                .accessibilityLabel("Show")
                Toggle("Follow", isOn: $follow).toggleStyle(.checkbox).fixedSize()
                    .frame(height: Theme.controlHeight)
                    .helped("Keep the newest output in view")
                TextSizeButtons(size: $textSize)
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(server.console.map(\.text).joined(separator: "\n"), forType: .string)
                }
                .buttonStyle(.themed)
                Button("Clear") { server.clearConsole() }.buttonStyle(.themed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            ConsoleTextView(lines: visible, signature: "\(filter)|\(minimumLevel.rawValue)|\(textSize)", follow: follow, size: textSize)
                .overlay { Rectangle().strokeBorder(Theme.border, lineWidth: 1) }
                .overlay {
                    if visible.isEmpty {
                        if server.console.isEmpty {
                            EmptyMessage(icon: "terminal", title: server.state.isLive ? "Waiting for output" : "The server is stopped",
                                         detail: server.state.isLive ? "Lines appear here as the server writes them." : "Its output appears here when it starts.")
                        } else {
                            EmptyMessage(icon: "line.3.horizontal.decrease", title: "No lines match", detail: "Clear the filter or choose All to see every line.")
                        }
                    }
                }

            HStack(spacing: 8) {
                Image(systemName: "chevron.right").foregroundStyle(Theme.accent).accessibilityHidden(true)
                TextField("Command", text: $command, prompt: Text(server.state.isLive ? "Type a command, such as list or say Hello" : "Start the server to send commands"))
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($commandFocused)
                    .disabled(!server.state.isLive)
                    .onSubmit(send)
                    .onKeyPress(.upArrow) { step(-1); return .handled }
                    .onKeyPress(.downArrow) { step(1); return .handled }
                    .accessibilityLabel("Server command")
                Button("Send", action: send).buttonStyle(.themed).disabled(command.isEmpty || !server.state.isLive)
            }
            .padding(12)
            .background(Theme.surface)
        }
        .onAppear { commandFocused = server.state.isLive }
    }

    private var visible: [ConsoleLine] {
        let needle = filter.lowercased()
        return server.console.filter {
            $0.level >= minimumLevel && (needle.isEmpty || $0.text.lowercased().contains(needle))
        }
    }

    private func send() {
        guard !command.isEmpty else { return }
        server.send(command)
        if history.last != command { history.append(command) }
        if history.count > 100 { history.removeFirst() }
        command = ""
        historyIndex = nil
    }

    private func step(_ delta: Int) {
        guard !history.isEmpty else { return }
        let next = (historyIndex ?? history.count) + delta
        if next >= history.count {
            historyIndex = nil
            command = ""
        } else {
            historyIndex = max(0, next)
            command = history[historyIndex!]
        }
    }
}

/// AppKit text view: selectable across lines, cheap to append to, and read properly by VoiceOver.
struct ConsoleTextView: NSViewRepresentable {
    let lines: [ConsoleLine]
    let signature: String
    let follow: Bool
    var size = TextZoom.standard

    final class Coordinator {
        var lastID = -1
        var signature = ""
        var firstID = -1
        var drawn = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.setAccessibilityLabel("Server output")
        text.setAccessibilityRole(.textArea)
        text.isRichText = false
        text.usesFontPanel = false
        text.drawsBackground = true
        text.backgroundColor = NSColor(Theme.surface)
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.layoutManager?.allowsNonContiguousLayout = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else { return }
        let c = context.coordinator
        // Rebuild when the filter changes or trimming has left too much behind; otherwise just append.
        let trimmedAway = (lines.first?.id ?? -1) != c.firstID && c.drawn > lines.count + 500
        let reset = c.signature != signature || lines.last.map { $0.id < c.lastID } ?? (c.lastID >= 0) || trimmedAway
        if reset {
            storage.setAttributedString(NSAttributedString())
            c.lastID = -1
            c.drawn = 0
            c.signature = signature
        }
        let fresh = lines.drop { $0.id <= c.lastID }
        guard !fresh.isEmpty else { return }
        let block = NSMutableAttributedString()
        for line in fresh { block.append(Self.render(line, size: size)) }
        storage.beginEditing()
        storage.append(block)
        storage.endEditing()
        c.lastID = lines.last?.id ?? -1
        c.firstID = lines.first?.id ?? -1
        c.drawn += fresh.count
        if follow { text.scrollToEndOfDocument(nil) }
    }

    private static func render(_ line: ConsoleLine, size: Double) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let color: Color
        switch (line.origin, line.level) {
        case (_, .error): color = Theme.danger
        case (_, .warn): color = Theme.warning
        case (.command, _): color = Theme.accent
        case (.wrapper, _): color = Theme.info
        default: color = Theme.ink
        }
        return NSAttributedString(string: line.displayText + "\n", attributes: [.font: font, .foregroundColor: NSColor(color)])
    }
}

/// Smaller and larger text, with Command-minus and Command-plus. Larger answers both + and = so it works without Shift.
struct TextSizeButtons: View {
    @Binding var size: Double
    var body: some View {
        HStack(spacing: 4) {
            Button { size = TextZoom.smaller(size) } label: { Image(systemName: "textformat.size.smaller") }
                .buttonStyle(.themed).keyboardShortcut("-", modifiers: .command)
                .disabled(size <= TextZoom.range.lowerBound)
                .helped("Smaller text (Command-minus)").accessibilityLabel("Smaller text")
            Button { size = TextZoom.larger(size) } label: { Image(systemName: "textformat.size.larger") }
                .buttonStyle(.themed).keyboardShortcut("+", modifiers: .command)
                .disabled(size >= TextZoom.range.upperBound)
                .helped("Larger text (Command-plus)").accessibilityLabel("Larger text")
            Button("") { size = TextZoom.larger(size) }.keyboardShortcut("=", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}
