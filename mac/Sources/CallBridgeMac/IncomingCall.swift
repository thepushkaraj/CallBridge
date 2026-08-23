import Foundation

struct IncomingCall {
    let event: String
    let number: String
    let caller: String
    let device: String
}

extension IncomingCall {
    static func from(jsonData: Data) -> IncomingCall? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: jsonData),
            let dict = obj as? [String: Any],
            let event = dict["event"] as? String
        else { return nil }

        return IncomingCall(
            event: event,
            number: dict["number"] as? String ?? "",
            caller: dict["caller"] as? String ?? "",
            device: dict["device"] as? String ?? ""
        )
    }
}
