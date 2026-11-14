import SwiftUI

// A restrained palette: grays carry the layout; the green accent appears only
// where it means something (the primary action, the ready-state dot).
// The QR stays on pure white in every appearance so cameras can always read it.
enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.33, green: 0.74, blue: 0.55, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.52, blue: 0.37, alpha: 1)
    })

    static let neutralTile = Color.primary.opacity(0.06)
    static let neutralStroke = Color.primary.opacity(0.12)

    static let warning = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.75, blue: 0.35, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.53, blue: 0.09, alpha: 1)
    })
}

// MARK: - Building blocks

/// The shared card treatment: raised surface, hairline edge, barely-there shadow.
private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 1)
    }
}

private extension View {
    func card() -> some View { modifier(CardBackground()) }
}

// MARK: - Root

struct AppView: View {
    @EnvironmentObject private var state: AppState
    @State private var notificationsDenied = false
    @State private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if notificationsDenied {
                warningRow(
                    icon: "bell.slash.fill",
                    text: "Notifications are turned off. Allow them for CallBridge in System Settings."
                )
            }

            if state.selectedIP.isEmpty {
                noNetworkCard
            } else {
                if case .failed(let message) = state.serverState {
                    failureCard(message)
                }

                Text("Pair your phone")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .padding(.bottom, -6)

                pairingCard

                if let event = state.lastEvent {
                    lastEventRow(event)
                }

                ConnectionSettingsView(expanded: $settingsExpanded)
                actionButtons
                footnote
            }
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: .notifierPermissionDenied)) { _ in
            notificationsDenied = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.neutralTile)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "phone.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("CallBridge")
                    .font(.system(size: 21, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            statusPill
        }
    }

    private var subtitle: String {
        if state.selectedIP.isEmpty { return "No network connection" }
        return "\(state.selectedIP)  ·  port \(state.port)"
    }

    private var statusPill: some View {
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

    // MARK: Pairing card

    private var pairingCard: some View {
        VStack(spacing: 16) {
            if let payload = state.pairingPayload, let image = QRCode.image(for: payload.jsonString) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 218, height: 218)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                    )
                    .accessibilityLabel("Pairing QR code for \(state.selectedIP) port \(state.port)")
            }

            Text("Scan with CallBridge on your Android phone")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Divider().opacity(0.6)

            VStack(alignment: .leading, spacing: 12) {
                step(1, "Install CallBridge on your Android phone")
                step(2, "Open it and tap \u{201C}Scan QR code\u{201D}")
                step(3, "Send a test to confirm the connection")
            }
        }
        .card()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().strokeBorder(Theme.neutralStroke, lineWidth: 1))
                .offset(y: 2)
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
        }
    }

    // MARK: Last event

    private func lastEventRow(_ event: AppState.LastEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: event.title == "Ringing" ? "phone.arrow.down.left.fill" : "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.neutralTile)
                )
            Text(event.detail.isEmpty ? event.title : "\(event.title) · \(event.detail)")
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(event.time, format: .dateTime.hour().minute())
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var actionButtons: some View {
        CopyFeedbackButton()
    }

    private var footnote: some View {
        Text("Calls stay on your Wi-Fi. An optional secret keeps other devices from posting to this Mac.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, -2)
    }

    private func warningRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.warning)
            Text(text)
                .font(.callout)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.warning.opacity(0.12))
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .systemRed).opacity(0.25), lineWidth: 1)
        )
    }

    private var noNetworkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No network address found", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text("Connect this Mac to your Wi-Fi network. The pairing code appears here as soon as the Mac has an address.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

// MARK: - Actions row

private struct CopyFeedbackButton: View {
    @EnvironmentObject private var state: AppState
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                state.sendTestNotification()
            } label: {
                Label("Send test notification", systemImage: "bell.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)

            Button {
                copyAddress()
            } label: {
                Label(copied ? "Copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func copyAddress() {
        let text = "\(state.selectedIP):\(state.port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run { copied = false }
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
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
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
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
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
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Apply") {
                            if let port = parsedPort {
                                state.applyConnection(port: port, secret: draftSecret.trimmingCharacters(in: .whitespaces))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(!hasChanges)

                        Text("Restarts the listener and updates the QR code.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
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
