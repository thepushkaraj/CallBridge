import Foundation

enum Notifier {
    static func handle(_ call: IncomingCall) {
        switch call.event {
        case "ringing":
            let who = [call.caller, call.number]
                .filter { !$0.isEmpty }
                .joined(separator: " \u{00B7} ")
            post(title: "Incoming call", body: who.isEmpty ? "Unknown caller" : who)
        case "test":
            let name = call.device.isEmpty ? "your phone" : call.device
            post(title: "CallBridge", body: "Test received from \(name) - you're connected")
        default:
            appLog("Ignoring unknown event: \(call.event)")
        }
    }

    private static func post(title: String, body: String) {
        let script =
            "display notification \"\(escaped(body))\" with title \"\(escaped(title))\" sound name \"Glass\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        do {
            try task.run()
        } catch {
            appLog("Failed to post notification: \(error.localizedDescription)")
        }
    }

    private static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
