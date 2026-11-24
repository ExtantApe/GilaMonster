import Foundation

/// The words of the Quit question when servers are running (K728). Kept here so the checks can read them.
public enum QuitWording {
    public struct Text: Equatable {
        public let title: String
        public let detail: String
        public let stopButton: String
    }

    public static func make(running: [String], leftOver: [String], packHost: Bool, sessionAccess: Bool) -> Text {
        let names = running + leftOver.filter { !running.contains($0) }
        let title = names.count == 1 ? "Quitting stops \(names[0])." : "Quitting stops \(names.count) servers."
        var lines: [String] = []
        if names.count > 1 { lines.append("Running: \(list(names)).") }
        lines.append("Players are disconnected and worlds saved first, which can take a minute.")
        if !leftOver.isEmpty { lines.append("\(list(leftOver)) \(leftOver.count == 1 ? "was" : "were") left running the last time GilaMonster closed.") }
        var also: [String] = []
        if packHost { also.append("the resource pack downloads") }
        if sessionAccess { also.append("session access") }
        if !also.isEmpty { lines.append("\(list(also).prefix(1).uppercased() + list(also).dropFirst()) stop with the app too.") }
        lines.append("To keep everything running, close the window instead. GilaMonster stays in the menu bar.")
        return Text(title: title, detail: lines.joined(separator: "\n\n"),
                    stopButton: names.count == 1 ? "Stop \(names[0]) and Quit" : "Stop Servers and Quit")
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
