import AppKit
import SwiftUI

setbuf(stdout, nil)

// MARK: - Options

struct Options {
    var port: UInt16?
    var secret: String?
    var headless = false
    var appearance: NSAppearance?
    #if DEBUG
    var renderPath: String?
    #endif
}

let usage = """
CallBridge - show a macOS notification when your Android phone rings

Usage: callbridge [--port <number>] [--secret <shared-secret>] [--headless] [--appearance <dark|light>]

  --port       TCP port to listen on (default: 8765)
  --secret     Require this shared secret in the X-CallBridge-Secret header
  --headless   Run without the app window (terminal-only, like early versions)
  --appearance Force light/dark mode (debugging aid)
"""

func parseOptions() -> Options {
    var options = Options()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = args.next() {
        switch arg {
        case "--port":
            guard let value = args.next(), let parsed = UInt16(value) else {
                print(usage)
                exit(2)
            }
            options.port = parsed
        case "--secret":
            guard let value = args.next() else {
                print(usage)
                exit(2)
            }
            options.secret = value
        case "--headless":
            options.headless = true
        #if DEBUG
        case "--render":
            // Debug aid: snapshot the window to a PNG after launch, then quit.
            guard let value = args.next() else {
                print(usage)
                exit(2)
            }
            options.renderPath = value
        #endif
        case "--appearance":
            guard let value = args.next() else {
                print(usage)
                exit(2)
            }
            switch value.lowercased() {
            case "dark": options.appearance = NSAppearance(named: .darkAqua)
            case "light": options.appearance = NSAppearance(named: .aqua)
            default:
                print(usage)
                exit(2)
            }
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            print("Unknown argument: \(arg). Try --help.")
            exit(2)
        }
    }
    return options
}

let options = parseOptions()

// MARK: - Headless (terminal-only) mode

if options.headless {
    let server = CallServer(port: options.port ?? AppState.defaultPort, secret: options.secret)
    server.onState = { state in
        switch state {
        case .ready:
            break // "listening" is printed by the server itself
        case .failed:
            exit(1)
        }
    }
    do {
        try server.start()
    } catch {
        print("Failed to start server: \(error)")
        print("Is another process using the port?")
        exit(1)
    }
    withExtendedLifetime(server) {
        RunLoop.main.run()
    }
}

// MARK: - App mode

let app = NSApplication.shared
let appState = AppState(portOverride: options.port, secretOverride: options.secret)
Notifier.prepareForNotifications()
appState.startServer()
appState.checkForUpdates()


final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    let forcedAppearance: NSAppearance?
    private var window: NSWindow?
    private var statusBar: StatusBarManager?

    init(appState: AppState, forcedAppearance: NSAppearance? = nil) {
        self.appState = appState
        self.forcedAppearance = forcedAppearance
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CallBridge"
        window.minSize = NSSize(width: 410, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AppView()
            .environmentObject(appState)
            .environmentObject(appState.history))
        window.center()
        window.makeKeyAndOrderFront(nil)

        #if DEBUG
        if let renderPath = options.renderPath {
            // Parked offscreen: the snapshot needs a laid-out, visible-style
            // window, not one the user has to watch flash by.
            window.setFrameOrigin(NSPoint(x: -32000, y: 32000))
            window.appearance = options.appearance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                defer { NSApp.terminate(nil) }
                guard let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                if let context = NSGraphicsContext(bitmapImageRep: rep) {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    NSColor.windowBackgroundColor.setFill()
                    view.bounds.fill(using: .sourceOver)
                    NSGraphicsContext.restoreGraphicsState()
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { return }
                try? data.write(to: URL(fileURLWithPath: renderPath))
            }
        }
        #endif
        self.window = window

        if let appearance = forcedAppearance {
            NSApp.appearance = appearance
        }

        let statusBar = StatusBarManager(
            appState: appState,
            showWindow: { [weak self] in self?.showWindow() }
        )
        statusBar.install()
        self.statusBar = statusBar

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // closing the window keeps the listener running
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let delegate = AppDelegate(appState: appState, forcedAppearance: options.appearance)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
