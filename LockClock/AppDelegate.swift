import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showSettingsNotification = Notification.Name("app.lockclock.LockClock.showSettings")

    private var controller: LockClockController?
    private var terminationSource: DispatchSourceSignal?
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installTerminationHandler()
        listenForReopenFromAnotherCopy()
        let controller = LockClockController()
        self.controller = controller
        controller.start()
    }

    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        terminationSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let settingsObserver {
            DistributedNotificationCenter.default().removeObserver(settingsObserver)
        }
        controller?.stop()
        controller = nil
    }

    private func listenForReopenFromAnotherCopy() {
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.showSettingsNotification,
            object: Bundle.main.bundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            self?.controller?.showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showSettings()
        return true
    }
}
