import Foundation
import UserNotifications

enum Notifier {
    /// Set before the run loop starts when running with UI, so banners show
    /// while the app is frontmost.
    private static let center = UNUserNotificationCenter.current()
    private static var usesUN: Bool { Bundle.main.bundleIdentifier != nil }

    static func prepareForNotifications() {
        guard usesUN else { return }
        center.delegate = NotifierDelegate.shared
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .notifierPermissionDenied, object: nil)
                }
            }
        }
    }

    /// Silent, informational notice (no sound) — e.g. manual update-check results.
    static func showNotice(title: String, body: String) {
        post(title: title, body: body, sound: false)
    }

    static func handle(_ call: IncomingEvent) {
        switch call.event {
        case "ringing":
            let who = [call.caller, call.number]
                .filter { !$0.isEmpty }
                .joined(separator: " \u{00B7} ")
            post(title: "Incoming call", body: who.isEmpty ? "Unknown caller" : who)
        case "sms":
            let who = [call.caller, call.number]
                .filter { !$0.isEmpty }
                .joined(separator: " \u{00B7} ")
            let sender = who.isEmpty ? "Unknown sender" : who
            post(title: "SMS from \(sender)", body: call.body.isEmpty ? "(no text)" : call.body)
        case "test":
            let name = call.device.isEmpty ? "your phone" : call.device
            post(title: "CallBridge", body: "Test received from \(name) - you're connected")
        default:
            appLog("Ignoring unknown event: \(call.event)")
        }
    }

    private static func post(title: String, body: String, sound: Bool = true) {
        if usesUN {
            postUN(title: title, body: body, sound: sound)
        } else {
            postOsascript(title: title, body: body, sound: sound)
        }
    }

    private static func postUN(title: String, body: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound {
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                appLog("Failed to post notification: \(error.localizedDescription)")
                postOsascript(title: title, body: body)
            }
        }
    }

    private static func postOsascript(title: String, body: String, sound: Bool = true) {
        let soundPart = sound ? " sound name \"Glass\"" : ""
        let script =
            "display notification \"\(escaped(body))\" with title \"\(escaped(title))\"\(soundPart)"
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
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

extension Notification.Name {
    static let notifierPermissionDenied = Notification.Name("callbridge.notificationsDenied")
}

/// Without a delegate, macOS suppresses banners while the app is frontmost.
final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifierDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
