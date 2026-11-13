import AppKit
import Foundation
import UserNotifications

enum Notifier {
    enum Category {
        static let smsCode = "sms-code"
        static let smsPlain = "sms-plain"
    }

    enum Action {
        static let copyCode = "copy-code"
        static let copyMessage = "copy-message"
    }

    private static let center = UNUserNotificationCenter.current()
    private static var usesUN: Bool { Bundle.main.bundleIdentifier != nil }

    static func prepareForNotifications() {
        guard usesUN else { return }
        center.delegate = NotifierDelegate.shared
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.smsCode,
                actions: [UNNotificationAction(identifier: Action.copyCode, title: "Copy code")],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.smsPlain,
                actions: [UNNotificationAction(identifier: Action.copyMessage, title: "Copy message")],
                intentIdentifiers: []
            ),
        ])
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
            let text = call.body.isEmpty ? "(no text)" : call.body
            let code = OTPExtractor.extract(from: text)
            let category = code != nil ? Category.smsCode : Category.smsPlain
            post(
                title: "SMS from \(sender)",
                body: text,
                category: category,
                userInfo: ["body": text, "code": code ?? ""]
            )
        case "test":
            let name = call.device.isEmpty ? "your phone" : call.device
            post(title: "CallBridge", body: "Test received from \(name) - you're connected")
        default:
            appLog("Ignoring unknown event: \(call.event)")
        }
    }

    /// Runs when the user taps an action button on a notification.
    /// Copies silently — no confirmation notification (macOS re-banners
    /// same-identifier replacements, so any visual feedback would repeat).
    static func handleAction(_ actionIdentifier: String, userInfo: [AnyHashable: Any]) {
        let isCode = actionIdentifier == Action.copyCode
        guard isCode || actionIdentifier == Action.copyMessage else { return }

        let info = userInfo as? [String: Any] ?? [:]
        let body = info["body"] as? String ?? ""
        let copied: String
        if isCode, let code = info["code"] as? String, !code.isEmpty {
            copied = code
        } else {
            copied = body
        }
        guard !copied.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copied, forType: .string)
        appLog("Copied to clipboard: \(isCode ? "code \(copied)" : "message")")
    }

    // MARK: - Posting

    private static func post(
        title: String,
        body: String,
        category: String? = nil,
        userInfo: [String: Any] = [:],
        sound: Bool = true
    ) {
        if usesUN {
            postUN(title: title, body: body, category: category, userInfo: userInfo, sound: sound)
        } else {
            postOsascript(title: title, body: body, sound: sound)
        }
    }

    private static func postUN(
        title: String,
        body: String,
        category: String?,
        userInfo: [String: Any],
        sound: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound {
            content.sound = .default
        }
        if let category {
            content.categoryIdentifier = category
        }
        if !userInfo.isEmpty {
            content.userInfo = userInfo
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

/// Pulls the most OTP-like token out of an SMS body.
enum OTPExtractor {
    // "Your OTP is 482913", "code: 482913", "verification code 482913"
    private static let keywordBefore = #"(?:otp|code|password|passcode|pin|verification|verify)\D{0,20}(\d{4,8})"#
    // "482913 is your verification code"
    private static let keywordAfter = #"(\d{4,8})\D{0,10}is your\b"#
    // Any standalone 4-8 digit number.
    private static let anyDigits = #"\b\d{4,8}\b"#

    /// Returns the most OTP-like token in the message, or nil when ambiguous.
    static func extract(from body: String) -> String? {
        if let match = firstGroup(keywordBefore, in: body) { return match }
        if let match = firstGroup(keywordAfter, in: body) { return match }

        // Bare-number fallback: only confident when exactly one standalone
        // number exists and it doesn't look like a customer-care line.
        let candidates = matches(anyDigits, in: body).filter { candidate in
            guard !candidate.hasPrefix("1800"), !candidate.hasPrefix("1860") else { return false }
            return !precededByCallWord(candidate, in: body)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func precededByCallWord(_ candidate: String, in body: String) -> Bool {
        guard let range = body.range(of: candidate) else { return false }
        let prefixStart = body.index(
            range.lowerBound,
            offsetBy: -12,
            limitedBy: body.startIndex
        ) ?? body.startIndex
        let prefix = String(body[prefixStart..<range.lowerBound]).lowercased()
        return ["call", "toll", "balance", "account", "a/c", "card", "no.", "order"]
            .contains { prefix.contains($0) }
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: range),
            match.numberOfRanges > 1,
            let group = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[group])
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

extension Notification.Name {
    static let notifierPermissionDenied = Notification.Name("callbridge.notificationsDenied")
}

/// Without a delegate, macOS suppresses banners while the app is frontmost,
/// and notification action taps are dropped.
final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifierDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Respect per-notification sound choice.
        completionHandler(notification.request.content.sound != nil ? [.banner, .sound] : [.banner])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Notifier.handleAction(response.actionIdentifier, userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}
