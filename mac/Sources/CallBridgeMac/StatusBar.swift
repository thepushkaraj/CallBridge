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
            button.image = Self.makeMenuIcon()
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

    /// The two-nodes-+-arc mark as a template image, so the menu bar tints it
    /// for light/dark appearance.
    private static func makeMenuIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setLineWidth(2)
            context.setLineCap(.round)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 3.5, y: 3.5))
            path.addQuadCurve(to: CGPoint(x: 14.5, y: 14.5), control: CGPoint(x: 14.5, y: 3.5))
            context.addPath(path)
            context.strokePath()
            context.fillEllipse(in: CGRect(x: 1, y: 1, width: 5, height: 5))
            context.fillEllipse(in: CGRect(x: 12, y: 12, width: 5, height: 5))
            return true
        }
        image.isTemplate = true
        return image
    }
}
