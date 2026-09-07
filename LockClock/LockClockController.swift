import AppKit

final class LockClockController {
    private let detector = LockScreenDetector()
    private let windowManager: SystemWindowManager
    private let displays: DisplayManager
    private var diagnostics: DiagnosticsWindowController?
    private var settingsWindow: SettingsWindowController?
    private var statusItem: StatusItemController?
    private var pendingShow: DispatchWorkItem?
    private let lockShowDelay: TimeInterval = 0.7

    init() {
        let appearance = Settings.shared.appearance
        if let skyLight = SkyLightBridge.makeManager(spaceLevel: appearance.skyLightSpaceLevel) {
            windowManager = skyLight
        } else {
            LockClockLog.error("SkyLight initialization failed")
            windowManager = AppKitWindowManager()
        }
        displays = DisplayManager(windowManager: windowManager)
    }

    func start() {
        LockClockLog.info("Started")
        displays.start()
        Settings.shared.onChange = { [weak self] in
            self?.handleSettingsChange()
        }
        detector.onStateChange = { [weak self] state in
            self?.handle(state)
        }
        detector.start()

        statusItem = StatusItemController(controller: self)

        if Settings.isDebugMode {
            showDiagnostics()
        }
        if Settings.shouldOpenSettingsOnLaunch {
            showSettings()
        }
        applyClockVisibility()
    }

    func stop() {
        detector.stop()
        pendingShow?.cancel()
        pendingShow = nil
        displays.stop()
        diagnostics?.close()
        diagnostics = nil
        settingsWindow?.close()
        settingsWindow = nil
        statusItem = nil
        LockClockLog.info("Stopped")
    }

    var diagnosticState: LockState { detector.state }
    var windowManagerStatus: String { windowManager.statusDescription }
    var currentSpace: UInt64 { windowManager.currentSpaceID() }
    var displaySummary: String { displays.diagnosticSummary }

    func forceShowClock() {
        guard Settings.forceShowClock else { return }
        displays.showClock()
    }

    func forceHideClock() {
        if detector.state == .locked { return }
        displays.hideClock()
    }

    func showDiagnostics() {
        if diagnostics == nil {
            diagnostics = DiagnosticsWindowController(controller: self)
        }
        diagnostics?.show()
    }

    func showSettings() {
        applyClockVisibility()
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.show()
    }

    private func handle(_ state: LockState) {
        applyClockVisibility()
        diagnostics?.reload()
    }

    private func handleSettingsChange() {
        if let skyLight = windowManager as? SkyLightWindowManager {
            skyLight.setSpaceLevel(Settings.shared.appearance.skyLightSpaceLevel)
        }
        applyClockVisibility()
        if LaunchAtLogin.isEnabled {
            displays.refreshAppearance()
        }
        statusItem?.reload()
        diagnostics?.reload()
    }

    private func applyClockVisibility() {
        pendingShow?.cancel()
        pendingShow = nil

        if !LaunchAtLogin.isEnabled {
            LockClockLog.info("Clock disabled")
            displays.hideClock()
            return
        }
        switch detector.state {
        case .locked:
            if displays.isShowing {
                displays.refreshAppearance()
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.detector.state == .locked, LaunchAtLogin.isEnabled else { return }
                LockClockLog.info("Showing clock")
                self.displays.showClock()
            }
            pendingShow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + lockShowDelay, execute: work)
        case .unlocked:
            if Settings.forceShowClock {
                LockClockLog.info("Force-show clock (debug)")
                displays.showClock()
            } else {
                LockClockLog.info("Hiding clock")
                displays.hideClock()
            }
        }
    }
}
