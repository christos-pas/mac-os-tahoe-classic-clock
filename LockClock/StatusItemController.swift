import AppKit

final class StatusItemController {
    private let item: NSStatusItem
    private weak var controller: LockClockController?

    init(controller: LockClockController) {
        self.controller = controller
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Lock Clock")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Lock Clock"
        reload()
    }

    func reload() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Lock Clock",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    @objc private func openSettings(_ sender: Any?) {
        controller?.showSettings()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
