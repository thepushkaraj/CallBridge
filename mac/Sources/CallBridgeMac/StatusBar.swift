import AppKit

/// Menu bar presence: a small phone glyph that keeps the server reachable
/// (Show window / Send test / Quit) even when the main window is closed.
final class StatusBarManager: NSObject {
    private let appState: AppState
    private let showWindow: () -> Void
    private var item: NSStatusItem?

    init(appState: AppState, showWindow: @escaping () -> Void) {
        self.appState = appState
        self.showWindow = showWindow
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(
                systemSymbolName: "iphone.radiowaves.left.and.right",
                accessibilityDescription: "CallBridge"
            )?.withSymbolConfiguration(config)
            if button.image == nil {
                button.title = "CB"
            }
        }

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show CallBridge", action: #selector(showClicked), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let test = NSMenuItem(title: "Send test notification", action: #selector(testClicked), keyEquivalent: "")
        test.target = self
        menu.addItem(test)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit CallBridge", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        self.item = item
    }

    @objc private func showClicked() { showWindow() }

    @objc private func testClicked() { appState.sendTestNotification() }

    @objc private func quitClicked() { NSApp.terminate(nil) }
}
