import Foundation

/// One event received over the wire: a call state, an SMS, or a test ping.
/// See PROTOCOL.md for the JSON schema.
struct IncomingEvent {
    let event: String
    let number: String
    let caller: String
    let device: String
    let body: String
}

extension IncomingEvent {
    static func from(jsonData: Data) -> IncomingEvent? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: jsonData),
            let dict = obj as? [String: Any],
            let event = dict["event"] as? String
        else { return nil }

        return IncomingEvent(
            event: event,
            number: dict["number"] as? String ?? "",
            caller: dict["caller"] as? String ?? "",
            device: dict["device"] as? String ?? "",
            body: dict["body"] as? String ?? ""
        )
    }
}
