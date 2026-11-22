import Combine
import Foundation

/// One received notification, kept so banners that were missed can be
/// reviewed later. Everything here stays on this Mac.
struct HistoryEntry: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case ringing
        case sms
        case test
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let title: String
    let detail: String
    /// Raw message text for sms entries; empty for calls and tests.
    let body: String

    enum CodingKeys: String, CodingKey {
        case id, date, kind, title, detail, body
    }

    init(id: UUID, date: Date, kind: Kind, title: String, detail: String, body: String = "") {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
        self.body = body
    }

    // Archives written before the body field existed decode cleanly.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        kind = try container.decode(Kind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
    }
}

extension HistoryEntry.Kind {
    /// Maps a wire event name to a history kind; unknown events are not
    /// recorded.
    init?(event: String) {
        switch event {
        case "ringing": self = .ringing
        case "sms": self = .sms
        case "test": self = .test
        default: return nil
        }
    }
}

/// Local-only record of received notifications: a JSON archive in
/// Application Support, newest first, capped at [maxEntries].
///
/// The switch pauses recording only; stored entries stay browsable and are
/// erased with the Clear button.
final class HistoryStore: ObservableObject {
    static let maxEntries = 200

    @Published private(set) var entries: [HistoryEntry] = []

    /// When false no new events are recorded; stored entries are kept.
    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
        }
    }

    private let archiveURL: URL
    private let writeQueue = DispatchQueue(label: "callbridge.history", qos: .utility)

    init(defaults: UserDefaults = .standard) {
        isEnabled = defaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
        archiveURL = Self.archiveURL()
        entries = Self.loadArchive(from: archiveURL)
    }

    /// Appends an entry at the top and persists the archive off the main
    /// thread. No-ops while history is disabled.
    func record(kind: HistoryEntry.Kind, title: String, detail: String, body: String = "") {
        guard isEnabled else { return }
        let entry = HistoryEntry(id: UUID(), date: Date(), kind: kind, title: title, detail: detail, body: body)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        persistSnapshot()
    }

    /// Erases every stored entry, on disk and in memory.
    func clear() {
        entries = []
        removeArchive()
    }

    private func persistSnapshot() {
        let snapshot = entries
        let url = archiveURL
        writeQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(snapshot).write(to: url, options: .atomic)
            } catch {
                appLog("History save failed: \(error.localizedDescription)")
            }
        }
    }

    private func removeArchive() {
        let url = archiveURL
        writeQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func loadArchive(from url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private static func archiveURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("CallBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.json")
    }

    private static let enabledDefaultsKey = "history_enabled"
}
