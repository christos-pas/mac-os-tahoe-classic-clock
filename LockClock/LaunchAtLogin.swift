import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if status == .enabled { return }
                try SMAppService.mainApp.register()
                LockClockLog.info("Launch at login enabled")
            } else {
                if status == .notRegistered { return }
                try SMAppService.mainApp.unregister()
                LockClockLog.info("Launch at Login disabled")
            }
        } catch {
            LockClockLog.error("Launch at login failed: \(error.localizedDescription)")
        }
    }

    static func registerIfNeeded() {
        if Settings.isDebugMode {
            LockClockLog.info("Debug mode: skipping automatic Launch at Login registration")
            return
        }
        guard !Settings.shared.hasAutoRegisteredLoginItem else { return }
        setEnabled(true)
        Settings.shared.hasAutoRegisteredLoginItem = true
    }
}
