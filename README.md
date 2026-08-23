# CallBridge

Get a native macOS notification the instant your Android phone rings.
~200 lines of logic per platform, zero third-party dependencies, no cloud,
no accounts. Your call metadata never leaves your Wi-Fi network.

```
[Android rings] --HTTP POST--> [Mac listener] --> [macOS notification]
```

## Why

Existing solutions (Pushbullet, KDE Connect) are either cloud relays that
see your call metadata, or full device-suites when you only wanted call
alerts. CallBridge does exactly one thing:

- **Android**: a `BroadcastReceiver` notices an incoming call and POSTs a
  tiny JSON event to your Mac over your local network.
- **Mac**: a small Swift listener receives it and shows a native
  notification.

That's the whole system. The entire wire protocol fits on one page — see
[PROTOCOL.md](PROTOCOL.md).

## Requirements

- Android 8.0+ (Oreo) phone
- macOS 12+ (Monterey)
- Both devices on the same Wi-Fi network
- Swift 5.9+ toolchain to *build* the Mac binary (users of a release don't need it)

## Setup (from source)

### 1. Mac — build and start the listener

```bash
cd mac
swift build -c release
.build/release/callbridge
```

You should see:

```
CallBridge listening on port 8765
```

Find your Mac's IP address if you need it:

```bash
ipconfig getifaddr en0   # usually Wi-Fi
```

### 2. Android — install the app

1. Open the `android/` folder in Android Studio and press Run, or build
   the APK from CI releases and sideload it.
2. Grant the phone-state permission when asked.
3. Enter your Mac's IP address (port defaults to `8765`).
4. Tap **Send test** — a notification should appear on your Mac.

### 3. Done

When someone calls your Android, your Mac now shows:
"Incoming call · +1 555 010 1234".

Optional: set a shared secret in both apps so only your phone can post
notifications to your Mac.

## Security model

Honest about what this is: LAN-only, plaintext HTTP, optional shared
secret header (`X-CallBridge-Secret`). It is designed for home networks,
not hostile ones. Nothing is stored, logged, or sent anywhere except your
own Mac.

## Roadmap

- [ ] v0.1 — ringing notifications, manual IP entry *(this release)*
- [ ] Missed-call events
- [ ] mDNS auto-discovery (no manual IP entry)
- [ ] Menu-bar `.app` bundle with QR-code pairing
- [ ] Signed DMG + APK releases
- [ ] Windows / Linux listeners speaking the same protocol

## Contributing

Start with [PROTOCOL.md](PROTOCOL.md) — the whole spec is one JSON blob.
Pick a platform folder; there are no cross-platform abstractions to learn.

## License

[MIT](LICENSE)
