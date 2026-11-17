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
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var upToDateNotice = false
    private var updateZipURL: URL?
    private var updateSigURL: URL?
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

    /// Manual checks surface feedback (notice/banner); launch checks stay
    /// silent when there's no update.
    func checkForUpdates(manual: Bool = false) {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        MacUpdateCenter.check { [weak self] outcome in
            guard let self else { return }
            self.isCheckingForUpdates = false
            switch outcome {
            case .available(let update):
                if self.availableUpdate != update.version {
                    self.availableUpdate = update.version
                    self.updateZipURL = update.zipURL
                    self.updateSigURL = update.sigURL
                }
                if manual {
                    Notifier.showNotice(
                        title: "Update available",
                        body: "Version \(update.version) is ready to download in CallBridge."
                    )
                }
            case .upToDate:
                if manual {
                    self.flashUpToDate()
                    Notifier.showNotice(
                        title: "You're up to date",
                        body: "CallBridge v\(MacUpdateCenter.currentVersion()) is the latest version."
                    )
                }
            case .failed:
                if manual {
                    Notifier.showNotice(
                        title: "Couldn't check for updates",
                        body: "The update check failed. Try again later."
                    )
                }
            }
        }
    }

    private func flashUpToDate() {
        upToDateNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.upToDateNotice = false
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
            guard let self, let zip, let sigURL = self.updateSigURL else {
                self?.updateState = .idle
                return
            }
            // Fail closed: the archive is only marked ready after its
            // Ed25519 signature checks out. Nothing is touched otherwise.
            MacUpdateCenter.fetchSignature(at: sigURL) { signature in
                guard
                    let signature,
                    MacUpdateCenter.isValidSignature(signature, forArchive: zip)
                else {
                    self.updateState = .idle
                    Notifier.showNotice(
                        title: "Update rejected",
                        body: "The downloaded update failed signature verification. Nothing was installed."
                    )
                    return
                }
                self.updateState = .ready
            }
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
        let call = IncomingEvent(event: "test", number: "", caller: "", device: "This Mac", body: "")
        record(call)
        Notifier.handle(call)
    }

    private func record(_ call: IncomingEvent) {
        let title: String
        let detail: String
        switch call.event {
        case "ringing":
            title = "Ringing"
            detail = [call.caller, call.number].filter { !$0.isEmpty }.joined(separator: " · ")
        case "sms":
            title = "SMS"
            let sender = [call.caller, call.number].filter { !$0.isEmpty }.joined(separator: " · ")
            detail = sender.isEmpty ? call.body : sender + " — " + call.body
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
