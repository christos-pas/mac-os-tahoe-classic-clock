import AppKit

if CommandLine.arguments.contains("--unregister-login-item") {
    LaunchAtLogin.setEnabled(false)
    exit(0)
}

let bundleID = Bundle.main.bundleIdentifier ?? "app.lockclock.LockClock"
let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if alreadyRunning {
    DistributedNotificationCenter.default().postNotificationName(
        AppDelegate.showSettingsNotification,
        object: bundleID,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
