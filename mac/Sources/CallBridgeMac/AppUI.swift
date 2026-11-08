import SwiftUI

// A restrained palette: system backgrounds, graphite text, one muted green accent.
// The QR stays on pure white in every appearance so cameras can always read it.
enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.37, green: 0.78, blue: 0.58, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.52, blue: 0.37, alpha: 1)
    })

    static let accentSoft = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.13, green: 0.28, blue: 0.21, alpha: 1)
            : NSColor(srgbRed: 0.86, green: 0.94, blue: 0.90, alpha: 1)
    })

    static let warning = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.75, blue: 0.35, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.53, blue: 0.09, alpha: 1)
    })
}

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    fileprivate func card() -> some View { modifier(CardBackground()) }
}

// MARK: - Root

struct AppView: View {
    @EnvironmentObject private var state: AppState
    @State private var notificationsDenied = false
    @State private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .frame(width: 430, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: .notifierPermissionDenied)) { _ in
            notificationsDenied = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.accentSoft)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("CallBridge").font(.headline)
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
        let (dot, label, soft): (Color, String, Color) = {
            switch state.serverState {
            case .listening:
                return (Theme.accent, "Ready", Theme.accentSoft)
            case .starting:
                return (Color.secondary, "Starting…", Color.primary.opacity(0.06))
            case .failed:
                return (Color(nsColor: .systemRed), "Not listening", Color(nsColor: .systemRed).opacity(0.12))
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(label).font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(soft))
    }

    // MARK: Pairing card

    private var pairingCard: some View {
        VStack(spacing: 16) {
            if let payload = state.pairingPayload, let image = QRCode.image(for: payload.jsonString) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 216, height: 216)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    )
                    .accessibilityLabel("Pairing QR code for \(state.selectedIP) port \(state.port)")
            }

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Install CallBridge on your Android phone")
                step(2, "Open it and tap \u{201C}Scan QR code\u{201D}")
                step(3, "Send a test to confirm the connection")
            }
        }
        .card()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.accentSoft))
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Last event

    private func lastEventRow(_ event: AppState.LastEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: event.title == "Ringing" ? "phone.arrow.down.left.fill" : "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(event.title == "Ringing" ? Theme.warning : Theme.accent)
            Text(event.detail.isEmpty ? event.title : "\(event.title) · \(event.detail)")
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(event.time, format: .dateTime.hour().minute())
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var actionButtons: some View {
        CopyFeedbackButton()
    }

    private var footnote: some View {
        Text("Calls stay on your Wi-Fi. An optional secret keeps other devices from posting to this Mac.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }

    private func warningRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.warning)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if state.availableIPs.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NETWORK ADDRESS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Picker("", selection: $draftIP) {
                                ForEach(state.availableIPs, id: \.self, content: Text.init)
                            }
                            .labelsHidden()
                        }
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PORT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            TextField("8765", text: $draftPort)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.monospacedDigit())
                                .frame(width: 110)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SHARED SECRET (OPTIONAL)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
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
                .padding(.top, 14)
            }
        }
        .card()
        .onAppear { seedDrafts() }
        .onChange(of: expanded) { isExpanded in
            if isExpanded { seedDrafts() }
        }
    }

    private func seedDrafts() {
        draftIP = state.selectedIP
        draftPort = String(state.port)
        draftSecret = state.secret
    }
}
