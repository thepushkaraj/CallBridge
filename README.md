<p align="left">
  <img src="docs/logo.png" width="128" height="128" alt="CallBridge Logo" />
</p>

# CallBridge

Get a native macOS notification the instant your Android phone rings
or a text message arrives. No cloud, no accounts. Everything stays on
your Wi-Fi network.

```
[Android rings / SMS] --HTTP POST--> [Mac listener] --> [macOS notification]
```

## Features

- **Incoming call alerts**: the moment your phone rings, a native macOS
  notification appears with the caller's name (from your contacts) or number
- **SMS forwarding** *(opt-in)*: received text messages show up on your Mac
  with the sender's name; off by default, and Android asks for the SMS
  permission only when you turn it on
- **One-tap OTP copy**: code-like messages get a `Copy code` action, detected
  entirely on-device; tapping copies the code to the Mac's clipboard
- **One-scan pairing**: the Mac shows a QR code, the phone scans it, done
  (manual address entry stays available)
- **Self-updating apps**: both apps check GitHub for new releases and update
  in place: download progress on Android, automatic swap-and-relaunch on the Mac
- **No cloud, no accounts**: a single JSON POST over your own Wi-Fi, optional
  shared secret, and the whole wire protocol fits on one page

## Why

Existing solutions (Pushbullet, KDE Connect) are either cloud relays that
see your call metadata, or full device-suites when you only wanted call
alerts. CallBridge does exactly one thing:

- **Android**: a `BroadcastReceiver` notices an incoming call (and, once
  you opt in, received SMS messages) and POSTs a tiny JSON event to your
  Mac over your local network.
- **Mac**: a small app shows the same event as a native notification
  and displays a QR code so pairing takes one scan.

That's the whole system. The entire wire protocol fits on one page. See
[PROTOCOL.md](PROTOCOL.md). The only dependencies are Apple's system
frameworks (Mac) and Google's AppCompat/Material/CameraX/ML Kit (Android);
QR scanning runs entirely on the phone.

## Requirements

- Android 8.0+ (Oreo) phone
- macOS 12+ (Monterey)
- Both devices on the same Wi-Fi network
- Swift 5.9+ toolchain to *build* the Mac app (users of a release don't need it)

## Setup (from source)

### 1. Mac: build and open the app

```bash
cd mac
./make_app.sh
open build/CallBridge.app
```

The window shows the address it's listening on, a QR code, and the three
pairing steps. macOS also asks to accept incoming network connections the
first time the app listens. Choose Allow. If that prompt is denied, the
phone cannot reach the Mac. (Terminal-only mode still works:
`.build/release/callbridge --headless --port 8765`.)

### 2. Android: install and pair

1. Open the `android/` folder in Android Studio and press Run, or build
   the APK from CI releases and sideload it.
2. Grant the phone-state permission when asked.
3. Tap **Scan QR code** and point the camera at the code on your Mac.
   (Manual entry stays available under *Enter address manually*.)
4. Tap **Send test** and a notification should appear on your Mac.

### 3. Done

When someone calls your Android, your Mac now shows:
"Incoming call · +1 555 010 1234".

Optional: set a shared secret on the Mac (Connection settings) and re-scan
the QR so only your phone can post notifications to it.

## Security model

Honest about what this is: LAN-only, plaintext HTTP, optional shared
secret header (`X-CallBridge-Secret`). It is designed for home networks,
not hostile ones. The phone only sends to a private address (`10/8`,
`172.16/12`, `192.168/16`, or `169.254/16`). A QR code or a typed address
outside those ranges is rejected. Pairing settings stay on the phone and
are excluded from Android backup.

Delivery is best-effort. Each event is one POST with a 4-second timeout
and no retry. If the Mac is asleep, or the Wi-Fi blip lasts longer than
that, the call or text is dropped.

## Releases

Prebuilt binaries are attached to every [GitHub release](https://github.com/thepushkaraj/CallBridge/releases):

- **Android**: `CallBridge-vX.Y.Z.apk`: sideload it (Android asks to allow installs from your browser once)
- **macOS**: `CallBridge-macOS.zip`. Unzip, drag to Applications. The first launch needs one approval (the app is not Apple-notarized): double-click it once. If macOS blocks it, choose **Done**, then open **System Settings → Privacy & Security** and click **Allow Anyway** next to the CallBridge message. This is only needed once. macOS also asks to accept incoming network connections. Choose **Allow**. If that prompt is denied, the phone cannot reach the Mac.

Already installed? The app checks GitHub on launch and offers the update in-app, or use **Check for updates** in the app. ([latest release](https://github.com/thepushkaraj/CallBridge/releases/latest)) One-time note: if you installed the v0.3.0 **Android** APK, uninstall it once before installing v0.3.1 or newer (the app switched to its permanent release signature in v0.3.1).

| Release | Highlights |
|---|---|
| [v0.4.2](https://github.com/thepushkaraj/CallBridge/releases/tag/v0.4.2) | Phone only sends to private LAN addresses; pairing secret is excluded from Android backup; Mac update restores the old app if the swap fails |
| [v0.4.1](https://github.com/thepushkaraj/CallBridge/releases/tag/v0.4.1) | Reliability: Android APK download timeouts, fail-safe Mac update swap |
| [v0.4.0](https://github.com/thepushkaraj/CallBridge/releases/tag/v0.4.0) | SMS forwarding: text messages appear as Mac notifications, with one-tap OTP copy |
| [v0.3.2](https://github.com/thepushkaraj/CallBridge/releases/tag/v0.3.2) | Android: app version now visible in the footer; download progress shows on the update button |
| [v0.3.1](https://github.com/thepushkaraj/CallBridge/releases/tag/v0.3.1) | Android fix release: updater points at the real GitHub API, APK is release-signed |
| [v0.3.0](https://github.com/thepushkaraj/CallBridge/releases/tag/v0.3.0) | In-app auto-updater, manual update checks, release-signed Android builds |
| [v0.2.0](https://github.com/thepushkaraj/CallBridge/releases/tag/v0.2.0) | QR-code pairing, Material redesign, new app identity |
| [v0.1.0](https://github.com/thepushkaraj/CallBridge/releases/tag/v0.1.0) | Call notifications to your Mac |

## Contributing

Start with [PROTOCOL.md](PROTOCOL.md). The whole spec is one JSON blob.
Pick a platform folder; there are no cross-platform abstractions to learn.

## License

[MIT](LICENSE)
