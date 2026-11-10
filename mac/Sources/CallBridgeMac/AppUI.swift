import SwiftUI

// Grays carry the layout; color appears only where it means something:
// the ready-state dot, the "Not listening" state, and the primary action.
// Hierarchy comes from typography and whitespace, not boxes — the QR is the
// only surfaced element (cameras need a white panel to read it).
enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.33, green: 0.74, blue: 0.55, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.52, blue: 0.37, alpha: 1)
    })

    static let warning = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.75, blue: 0.35, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.53, blue: 0.09, alpha: 1)
    })

    static let hairline = Color.primary.opacity(0.08)
}

/// The primary action: neutral-prominent (near-black in light mode, near-white
/// in dark). Color is reserved for meaning — this button deliberately has none.
private struct NeutralProminentButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 6 : 9)
            .frame(maxWidth: compact ? nil : .infinity)
            .foregroundStyle(Color(nsColor: .controlBackgroundColor))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.75 : 1))
            )
    }
}

// MARK: - Root

struct AppView: View {
    @EnvironmentObject private var state: AppState
    @State private var notificationsDenied = false
    @State private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(Theme.hairline)
                .padding(.top, 18)
                .padding(.bottom, 22)

            if state.availableUpdate != nil {
                UpdateBanner()
                    .padding(.bottom, 20)
            }

            if notificationsDenied {
                warningRow(
                    icon: "bell.slash.fill",
                    text: "Notifications are turned off. Allow them for CallBridge in System Settings."
                )
                .padding(.bottom, 20)
            }

            if state.selectedIP.isEmpty {
                noNetworkView
            } else {
                if case .failed(let message) = state.serverState {
                    failureCard(message)
                        .padding(.bottom, 20)
                }

                PairingSection(payload: state.pairingPayload, ip: state.selectedIP)
                    .padding(.top, 4)
                    .padding(.bottom, 24)

                if let event = state.lastEvent {
                    LastEventRow(event: event)
                        .padding(.bottom, 20)
                }

                ConnectionSettingsView(expanded: $settingsExpanded)
                    .padding(.bottom, 20)

                actionButtons

                Divider()
                    .overlay(Theme.hairline)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                footnote
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(width: 440, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: .notifierPermissionDenied)) { _ in
            notificationsDenied = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CallBridge")
                    .font(.system(size: 20, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            statusView
                .padding(.top, 2)
        }
    }

    private var subtitle: String {
        if state.selectedIP.isEmpty { return "No network connection" }
        return "\(state.selectedIP)  ·  port \(state.port)"
    }

    private var statusView: some View {
        let (dot, label): (Color, String) = {
            switch state.serverState {
            case .listening:
                return (Theme.accent, "Ready")
            case .starting:
                return (Color.secondary, "Starting…")
            case .failed:
                return (Color(nsColor: .systemRed), "Not listening")
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    // MARK: Actions

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                state.sendTestNotification()
            } label: {
                Label("Send test notification", systemImage: "bell.fill")
            }
            .buttonStyle(NeutralProminentButtonStyle())

            CopyAddressButton()
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var footnote: some View {
        VStack(spacing: 8) {
            Text("Calls stay on your Wi-Fi. An optional secret keeps other devices from posting to this Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Text("v\(MacUpdateCenter.currentVersion())")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Button {
                    state.checkForUpdates(manual: true)
                } label: {
                    Text(state.upToDateNotice ? "You're up to date ✓" : (state.isCheckingForUpdates ? "Checking…" : "Check for updates"))
                        .font(.caption)
                        .foregroundStyle(state.upToDateNotice ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(state.isCheckingForUpdates)
            }
        }
    }

    private func warningRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.warning)
            Text(text)
                .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.warning.opacity(0.10))
        )
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Listener not running", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.warning)
            Text("\(message). The QR code below still shows the intended setup.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Try again") { state.startServer() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Change port…") {
                    withAnimation(.easeInOut(duration: 0.18)) { settingsExpanded = true }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.08))
        )
    }

    private var noNetworkView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No network address found", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text("Connect this Mac to your Wi-Fi network. The pairing code appears here as soon as the Mac has an address.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

// MARK: - Logomark
// The app icon's mark (two nodes + bridge arc), drawn as vectors so it
// adapts to appearance. Not used in the main window (the header is pure
// typography); kept for future surfaces like an About pane.

struct Logomark: View {
    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 18
            ZStack {
                BridgeArcShape()
                    .stroke(
                        LinearGradient(
                            colors: [Color.primary, Theme.accent],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        style: StrokeStyle(lineWidth: 1.55 * unit, lineCap: .round)
                    )
                Circle()
                    .fill(Color.primary)
                    .frame(width: 6.5 * unit, height: 6.5 * unit)
                    .position(x: 4 * unit, y: 14 * unit)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6.5 * unit, height: 6.5 * unit)
                    .position(x: 14 * unit, y: 4 * unit)
            }
        }
    }
}

/// The bridge arc in an 18×18 design space (y-down), bulging bottom-right.
struct BridgeArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 4, y: 14))
            p.addQuadCurve(
                to: CGPoint(x: 14, y: 4),
                control: CGPoint(x: 14, y: 14)
            )
        }
        .applying(CGAffineTransform(
            scaleX: rect.width / 18,
            y: rect.height / 18
        ))
    }
}

// MARK: - Update banner
// Slim always-visible row when a newer release exists: Download → progress
// percentage → Restart to update (swaps the bundle and relaunches).

private struct UpdateBanner: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                if let version = state.availableUpdate {
                    Text("Update available · v\(version)")
                        .font(.callout.weight(.semibold))
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                state.startUpdateDownload()
            } label: {
                Text(buttonLabel)
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(NeutralProminentButtonStyle(compact: true))
            .disabled(isDownloading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent.opacity(0.12))
        )
    }

    private var isDownloading: Bool {
        if case .downloading = state.updateState { return true }
        return false
    }

    private var caption: String {
        switch state.updateState {
        case .downloading(let fraction): return "Downloading… \(Int(fraction * 100))%"
        case .ready: return "Download complete — restart to finish the update"
        default: return "Download and install the latest version"
        }
    }

    private var buttonLabel: String {
        switch state.updateState {
        case .downloading(let fraction): return "\(Int(fraction * 100))%"
        case .ready: return "Restart to update"
        default: return "Download"
        }
    }
}

// MARK: - Pairing section
// Self-contained so the future Pair · History · Settings tab split can lift
// it straight out of AppView.

struct PairingSection: View {
    let payload: PairingPayload?
    let ip: String

    var body: some View {
        VStack(spacing: 18) {
            if let payload, let image = QRCode.image(for: payload.jsonString) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 222, height: 222)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                    )
                    .accessibilityLabel("Pairing QR code for \(ip) port \(payload.port)")
            }

            Text("Scan with CallBridge on your Android phone")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                step(1, "Install CallBridge on your Android phone")
                step(2, "Open it and tap \u{201C}Scan QR code\u{201D}")
                step(3, "Send a test to confirm the connection")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Last event row
// The template for the future history list.

struct LastEventRow: View {
    let event: AppState.LastEvent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.title == "Ringing" ? "phone.arrow.down.left.fill" : "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(event.detail.isEmpty ? event.title : "\(event.title) · \(event.detail)")
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(event.time, format: .dateTime.hour().minute())
                .font(.callout.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(for title: String) -> String {
        switch title {
        case "Ringing": return "phone.arrow.down.left.fill"
        case "SMS": return "message.fill"
        default: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Copy address button

private struct CopyAddressButton: View {
    @EnvironmentObject private var state: AppState
    @State private var copied = false

    var body: some View {
        Button {
            let text = "\(state.selectedIP):\(state.port)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                await MainActor.run { copied = false }
            }
        } label: {
            Label(copied ? "Copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
    }
}

// MARK: - Connection settings

private struct ConnectionSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Binding var expanded: Bool
    @State private var draftIP: String = ""
    @State private var draftPort: String = ""
    @State private var draftSecret: String = ""

    private var parsedPort: UInt16? {
        guard let value = UInt16(draftPort.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    private var hasChanges: Bool {
        guard let port = parsedPort else { return false }
        return draftIP != state.selectedIP || port != state.port || draftSecret != state.secret
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if !expanded {
                    seedDrafts()
                }
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Connection settings")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.leading, 2)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    if state.availableIPs.count > 1 {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Network address")
                            Picker("", selection: $draftIP) {
                                ForEach(state.availableIPs, id: \.self, content: Text.init)
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Port")
                            TextField("8765", text: $draftPort)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.monospacedDigit())
                                .frame(width: 110)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Shared secret (optional)")
                            SecureField("none", text: $draftSecret)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Apply") {
                            if let port = parsedPort {
                                state.applyConnection(port: port, secret: draftSecret.trimmingCharacters(in: .whitespaces))
                            }
                        }
                        .buttonStyle(NeutralProminentButtonStyle(compact: true))
                        .disabled(!hasChanges)

                        Text("Restarts the listener and updates the QR code.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 14)
                .padding(.leading, 2)
            }
        }
        .onAppear { seedDrafts() }
        .onChange(of: expanded) { isExpanded in
            if isExpanded { seedDrafts() }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }

    private func seedDrafts() {
        draftIP = state.selectedIP
        draftPort = String(state.port)
        draftSecret = state.secret
    }
}
