import Combine
import Foundation

/// Connection + UI state for the app window. Owns the server lifecycle so the
/// QR code, status line and settings stay in sync. Only ever touched on the
/// main thread; server callbacks hop back with DispatchQueue.main.
final class AppState: ObservableObject {
    enum ServerState: Equatable {
        case starting
        case listening
        case failed(String)
    }

    struct LastEvent: Equatable {
        let title: String
        let detail: String
        let time: Date
    }

    @Published private(set) var port: UInt16
    @Published private(set) var secret: String
    @Published private(set) var availableIPs: [String]
    @Published var selectedIP: String
    @Published private(set) var serverState: ServerState = .starting
    @Published private(set) var lastEvent: LastEvent?

    private var server: CallServer?

    // MARK: App update

    enum UpdateDownloadState: Equatable {
        case idle
        case downloading(Double)
        case ready
    }

    @Published private(set) var availableUpdate: String?
    @Published private(set) var updateState: UpdateDownloadState = .idle
    private var updateZipURL: URL?
    private lazy var updateDownloader = UpdateDownloader()

    static let defaultsPortKey = "port"
    static let defaultsSecretKey = "secret"
    static let defaultPort: UInt16 = 8765

    init(portOverride: UInt16? = nil, secretOverride: String? = nil) {
        let defaults = UserDefaults.standard
        let storedPort = UInt16(defaults.integer(forKey: Self.defaultsPortKey))
        let storedSecret = defaults.string(forKey: Self.defaultsSecretKey) ?? ""

        port = portOverride ?? (storedPort != 0 ? storedPort : Self.defaultPort)
        secret = secretOverride ?? storedSecret
        if let portOverride { defaults.set(Int(portOverride), forKey: Self.defaultsPortKey) }
        if let secretOverride { defaults.set(secretOverride, forKey: Self.defaultsSecretKey) }

        let ips = NetworkAddresses.preferredIPv4Addresses()
        availableIPs = ips
        selectedIP = ips.first ?? ""
    }

    var isListening: Bool { serverState == .listening }

    func checkForUpdates() {
        MacUpdateCenter.check { [weak self] update in
            guard let self, let update else { return }
            if self.availableUpdate != update.version {
                self.availableUpdate = update.version
                self.updateZipURL = update.zipURL
            }
        }
    }

    /// Downloads when idle; installs the already-downloaded update when ready.
    func startUpdateDownload() {
        if updateState == .ready {
            MacUpdateCenter.installDownloadedUpdate()
            return
        }
        guard updateState == .idle, let zipURL = updateZipURL else { return }
        updateState = .downloading(0)
        updateDownloader.onProgress = { [weak self] fraction in
            self?.updateState = .downloading(fraction)
        }
        updateDownloader.onComplete = { [weak self] zip in
            guard let self else { return }
            self.updateState = (zip != nil) ? .ready : .idle
        }
        updateDownloader.download(from: zipURL)
    }

    /// Payload encoded into the QR code; nil when there is no address to pair with.
    var pairingPayload: PairingPayload? {
        guard !selectedIP.isEmpty else { return nil }
        return PairingPayload(host: selectedIP, port: port, secret: secret.isEmpty ? nil : secret)
    }

    func startServer() {
        server?.stop()
        server = nil
        serverState = .starting

        let newServer = CallServer(port: port, secret: secret.isEmpty ? nil : secret)
        newServer.onEvent = { [weak self] call in
            DispatchQueue.main.async { self?.record(call) }
        }
        newServer.onState = { [weak self] serverState in
            DispatchQueue.main.async {
                switch serverState {
                case .ready: self?.serverState = .listening
                case .failed(let message): self?.serverState = .failed(message)
                }
            }
        }
        do {
            try newServer.start()
            server = newServer
        } catch {
            serverState = .failed("Could not open port \(port): \(error.localizedDescription)")
        }
    }

    func applyConnection(port newPort: UInt16, secret newSecret: String) {
        port = newPort
        secret = newSecret
        let defaults = UserDefaults.standard
        defaults.set(Int(newPort), forKey: Self.defaultsPortKey)
        defaults.set(newSecret, forKey: Self.defaultsSecretKey)
        startServer()
    }

    func sendTestNotification() {
        let call = IncomingCall(event: "test", number: "", caller: "", device: "This Mac")
        record(call)
        Notifier.handle(call)
    }

    private func record(_ call: IncomingCall) {
        let title: String
        let detail: String
        switch call.event {
        case "ringing":
            title = "Ringing"
            detail = [call.caller, call.number].filter { !$0.isEmpty }.joined(separator: " · ")
        case "test":
            title = "Test received"
            detail = call.device.isEmpty ? "phone" : call.device
        default:
            title = call.event
            detail = ""
        }
        lastEvent = LastEvent(title: title, detail: detail, time: Date())
    }
}
