import AppKit

final class DisplayManager {
    private(set) var clockWindows: [CGDirectDisplayID: LockScreenWindowController] = [:]
    private let windowManager: SystemWindowManager
    private(set) var isShowing = false
    private var screenObserver: NSObjectProtocol?
    private var wallpaperObserver: NSObjectProtocol?
    private var systemClockObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    init(windowManager: SystemWindowManager) {
        self.windowManager = windowManager
    }

    func start() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }
        wallpaperObserver = NotificationCenter.default.addObserver(
            forName: WallpaperImage.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            WallpaperBackdropBlur.clearCache()
            self?.refreshAppearance()
        }
        systemClockObserver = NotificationCenter.default.addObserver(
            forName: AppleLockScreenClock.preferencesDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAppearance()
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAppearance()
        }
        AppleLockScreenClock.startWatchingPreferences()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let wallpaperObserver {
            NotificationCenter.default.removeObserver(wallpaperObserver)
        }
        if let systemClockObserver {
            NotificationCenter.default.removeObserver(systemClockObserver)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        hideClock()
        clockWindows.removeAll()
    }

    func showClock() {
        isShowing = true
        reconcileWindows(showing: true)
        windowManager.showOverlaySpace()
    }

    func hideClock() {
        isShowing = false
        for controller in clockWindows.values {
            controller.hide(using: windowManager)
        }
        windowManager.hideOverlaySpace()
    }

    func refreshAppearance() {
        guard isShowing else { return }
        reconcileWindows(showing: true)
    }

    var diagnosticSummary: String {
        let lines = clockWindows.values.map { controller in
            "\(controller.screenName) frame=\(controller.diagnosticFrame) level=\(controller.diagnosticLevel)"
        }
        return lines.isEmpty ? "no clock windows" : lines.joined(separator: "\n")
    }

    private func handleScreenChange() {
        let attached = Set(NSScreen.screens.map(\.displayID))
        let stale = clockWindows.keys.filter { !attached.contains($0) }
        for displayID in stale {
            clockWindows[displayID]?.hide(using: windowManager)
            clockWindows.removeValue(forKey: displayID)
            LockClockLog.info("Removed stale clock window for detached display \(displayID)")
        }
        if isShowing {
            reconcileWindows(showing: true)
        }
    }

    private func reconcileWindows(showing: Bool) {
        let screens = NSScreen.screens
        let attached = Set(screens.map(\.displayID))
        for displayID in clockWindows.keys where !attached.contains(displayID) {
            clockWindows[displayID]?.hide(using: windowManager)
            clockWindows.removeValue(forKey: displayID)
        }

        for screen in screens {
            let controller = clockWindows[screen.displayID] ?? {
                LockClockLog.info("Creating window for display: \(screen.localizedName)")
                let created = LockScreenWindowController(screen: screen)
                clockWindows[screen.displayID] = created
                return created
            }()
            if showing {
                controller.show(using: windowManager, on: screen)
            }
        }
    }
}
