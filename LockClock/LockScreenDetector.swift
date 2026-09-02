import AppKit
import Foundation

enum LockState: String, Equatable {
    case unlocked
    case locked
}

/// Observes lock/unlock without treating session resign-active as lock.
///
/// Primary signals (verified public / long-standing system notifications):
/// - `com.apple.screenIsLocked`
/// - `com.apple.screenIsUnlocked`
/// - `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`
///
/// These fire for Control-Command-Q and for automatic lock when
/// “require password” is enabled. `NSWorkspace.sessionDidResignActive`
/// is Fast User Switch / console loss and is *not* treated as lock.
final class LockScreenDetector {
    var onStateChange: ((LockState) -> Void)?

    private(set) var state: LockState = .unlocked
    private var observers: [NSObjectProtocol] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, name: Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            LockClockLog.info("Notification: com.apple.screenIsLocked")
            self?.apply(.locked, reason: "screenIsLocked")
        }
        observe(distributed, name: Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            LockClockLog.info("Notification: com.apple.screenIsUnlocked")
            self?.apply(.unlocked, reason: "screenIsUnlocked")
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, name: NSWorkspace.didWakeNotification) { [weak self] in
            LockClockLog.info("Notification: NSWorkspace.didWake")
            self?.refreshFromSession(reason: "didWake")
        }
        observe(workspace, name: NSWorkspace.willSleepNotification) { [weak self] in
            LockClockLog.info("Notification: NSWorkspace.willSleep")
            self?.refreshFromSession(reason: "willSleep")
        }
        observe(workspace, name: NSWorkspace.screensDidSleepNotification) { [weak self] in
            LockClockLog.info("Notification: NSWorkspace.screensDidSleep")
            self?.refreshFromSession(reason: "screensDidSleep")
        }
        observe(workspace, name: NSWorkspace.screensDidWakeNotification) { [weak self] in
            LockClockLog.info("Notification: NSWorkspace.screensDidWake")
            self?.refreshFromSession(reason: "screensDidWake")
        }
        observe(workspace, name: NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            LockClockLog.info("Notification: sessionDidResignActive (not treated as lock)")
            self?.apply(.unlocked, reason: "sessionDidResignActive")
        }
        observe(workspace, name: NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            LockClockLog.info("Notification: sessionDidBecomeActive")
            self?.refreshFromSession(reason: "sessionDidBecomeActive")
        }

        refreshFromSession(reason: "startup")
    }

    func stop() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        for observer in observers {
            distributed.removeObserver(observer)
            workspace.removeObserver(observer)
            local.removeObserver(observer)
        }
        observers.removeAll()
        started = false
    }

    func refreshFromSession(reason: String) {
        let locked = Self.isScreenLocked()
        let onConsole = Self.isOnConsole()
        let next: LockState = (locked && onConsole) ? .locked : .unlocked
        apply(next, reason: reason)
    }

    static func sessionSnapshot() -> [String: String] {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return ["error": "CGSessionCopyCurrentDictionary returned nil"]
        }
        var snapshot: [String: String] = [:]
        for (key, value) in dict {
            snapshot[key] = String(describing: value)
        }
        return snapshot
    }

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return (dict["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    static func isOnConsole() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return true
        }
        if let value = dict["kCGSSessionOnConsoleKey"] as? NSNumber {
            return value.boolValue
        }
        return true
    }

    private func apply(_ next: LockState, reason: String) {
        guard next != state else { return }
        state = next
        LockClockLog.info("Session state changed: \(next.rawValue) (\(reason))")
        onStateChange?(next)
    }

    private func observe(
        _ center: NotificationCenter,
        name: Notification.Name,
        handler: @escaping () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            handler()
        }
        observers.append(token)
    }
}
