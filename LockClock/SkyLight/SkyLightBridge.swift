import AppKit
import Foundation

/// Loads verified SkyLight symbols with `dlopen`/`dlsym` and manages a
/// dedicated overlay Space used to appear on the macOS Lock Screen.
///
/// Signatures match Lakr233/SkyLightWindow and were confirmed against the
/// SkyLight binary on macOS 26.6.2 (25G83):
///
/// - `SLSMainConnectionID()` → connection `646699` on this machine
/// - `SLSSpaceCreate(cid, 1, 0)` → non-zero space id
/// - `SLSSpaceSetAbsoluteLevel(cid, sid, 400)` → level reads back as 400
/// - `SLSShowSpaces` / `SLSHideSpaces` / `SLSSpaceDestroy` → `0`
/// - `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, sid, [windowNumber], 7)` → `0`
final class SkyLightWindowManager: SystemWindowManager {
    private typealias F_SLSMainConnectionID = @convention(c) () -> Int32
    private typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SLSSpaceGetAbsoluteLevel = @convention(c) (Int32, Int32) -> Int32
    private typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias F_SLSHideSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias F_SLSSpaceDestroy = @convention(c) (Int32, Int32) -> Int32
    private typealias F_SLSGetActiveSpace = @convention(c) (Int32) -> UInt64

    private let handle: UnsafeMutableRawPointer
    private let SLSMainConnectionID: F_SLSMainConnectionID
    private let SLSSpaceCreate: F_SLSSpaceCreate
    private let SLSSpaceSetAbsoluteLevel: F_SLSSpaceSetAbsoluteLevel
    private let SLSSpaceGetAbsoluteLevel: F_SLSSpaceGetAbsoluteLevel
    private let SLSShowSpaces: F_SLSShowSpaces
    private let SLSHideSpaces: F_SLSHideSpaces
    private let SLSSpaceAddWindowsAndRemoveFromSpaces: F_SLSSpaceAddWindowsAndRemoveFromSpaces
    private let SLSSpaceDestroy: F_SLSSpaceDestroy
    private let SLSGetActiveSpace: F_SLSGetActiveSpace

    let connectionID: Int32
    let spaceID: Int32
    private(set) var spaceLevel: Int32
    private var overlayVisible = false

    var isAvailable: Bool { connectionID != 0 && spaceID != 0 }

    var statusDescription: String {
        guard isAvailable else { return "unavailable" }
        return "connected cid=\(connectionID) space=\(spaceID) level=\(spaceLevel) shown=\(overlayVisible)"
    }

    /// Space absolute levels used by WindowServer. Lock Screen is 300;
    /// Notification Center on the Lock Screen is 400. 400 is the level
    /// SkyLightWindow uses to appear on the Lock Screen without covering
    /// VoiceOver (600).
    enum SpaceLevel {
        static let screenLock: Int32 = 300
        static let notificationCenterAtScreenLock: Int32 = 400
    }

    init?(spaceLevel: Int32 = SpaceLevel.notificationCenterAtScreenLock) {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ) else {
            LockClockLog.error("SkyLight initialization failed")
            return nil
        }
        self.handle = handle

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }

        guard
            let SLSMainConnectionID = load("SLSMainConnectionID", as: F_SLSMainConnectionID.self),
            let SLSSpaceCreate = load("SLSSpaceCreate", as: F_SLSSpaceCreate.self),
            let SLSSpaceSetAbsoluteLevel = load("SLSSpaceSetAbsoluteLevel", as: F_SLSSpaceSetAbsoluteLevel.self),
            let SLSSpaceGetAbsoluteLevel = load("SLSSpaceGetAbsoluteLevel", as: F_SLSSpaceGetAbsoluteLevel.self),
            let SLSShowSpaces = load("SLSShowSpaces", as: F_SLSShowSpaces.self),
            let SLSHideSpaces = load("SLSHideSpaces", as: F_SLSHideSpaces.self),
            let SLSSpaceAddWindowsAndRemoveFromSpaces = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self),
            let SLSSpaceDestroy = load("SLSSpaceDestroy", as: F_SLSSpaceDestroy.self),
            let SLSGetActiveSpace = load("SLSGetActiveSpace", as: F_SLSGetActiveSpace.self)
        else {
            LockClockLog.error("SkyLight initialization failed")
            return nil
        }

        self.SLSMainConnectionID = SLSMainConnectionID
        self.SLSSpaceCreate = SLSSpaceCreate
        self.SLSSpaceSetAbsoluteLevel = SLSSpaceSetAbsoluteLevel
        self.SLSSpaceGetAbsoluteLevel = SLSSpaceGetAbsoluteLevel
        self.SLSShowSpaces = SLSShowSpaces
        self.SLSHideSpaces = SLSHideSpaces
        self.SLSSpaceAddWindowsAndRemoveFromSpaces = SLSSpaceAddWindowsAndRemoveFromSpaces
        self.SLSSpaceDestroy = SLSSpaceDestroy
        self.SLSGetActiveSpace = SLSGetActiveSpace

        let connectionID = SLSMainConnectionID()
        guard connectionID != 0 else {
            LockClockLog.error("SkyLight initialization failed")
            return nil
        }

        let spaceID = SLSSpaceCreate(connectionID, 1, 0)
        guard spaceID != 0 else {
            LockClockLog.error("SkyLight initialization failed")
            return nil
        }

        self.connectionID = connectionID
        self.spaceID = spaceID
        self.spaceLevel = spaceLevel
        _ = SLSSpaceSetAbsoluteLevel(connectionID, spaceID, spaceLevel)
        LockClockLog.info("SkyLight ready cid=\(connectionID) space=\(spaceID) level=\(spaceLevel)")
    }

    deinit {
        hideOverlaySpace()
        _ = SLSSpaceDestroy(connectionID, spaceID)
    }

    func setSpaceLevel(_ level: Int32) {
        spaceLevel = level
        _ = SLSSpaceSetAbsoluteLevel(connectionID, spaceID, level)
    }

    func promote(_ window: NSWindow, for screen: NSScreen) {
        guard window.windowNumber > 0 else {
            LockClockLog.error("SkyLight promotion skipped: windowNumber is 0 on \(screen.localizedName)")
            return
        }
        showOverlaySpace()
        let result = SLSSpaceAddWindowsAndRemoveFromSpaces(
            connectionID,
            spaceID,
            [window.windowNumber] as CFArray,
            7
        )
        if result == 0 {
            LockClockLog.info("SkyLight promotion successful")
        } else {
            LockClockLog.error("SkyLight promotion failed status=\(result)")
        }
    }

    func demote(_ window: NSWindow) {
        window.orderOut(nil)
    }

    func showOverlaySpace() {
        guard !overlayVisible else { return }
        _ = SLSShowSpaces(connectionID, [spaceID] as CFArray)
        overlayVisible = true
    }

    func hideOverlaySpace() {
        guard overlayVisible else { return }
        _ = SLSHideSpaces(connectionID, [spaceID] as CFArray)
        overlayVisible = false
    }

    func currentSpaceID() -> UInt64 {
        SLSGetActiveSpace(connectionID)
    }

    func currentAbsoluteLevel() -> Int32 {
        SLSSpaceGetAbsoluteLevel(connectionID, spaceID)
    }
}

enum SkyLightBridge {
    static func makeManager(spaceLevel: Int32) -> SystemWindowManager? {
        SkyLightWindowManager(spaceLevel: spaceLevel)
    }
}

/// Public-API fallback used only if SkyLight cannot be initialized.
/// Window levels stay inside the current Space and are not expected
/// to appear on the Tahoe Lock Screen.
final class AppKitWindowManager: SystemWindowManager {
    let connectionID: Int32 = 0
    let spaceID: Int32 = 0
    let spaceLevel: Int32 = 0
    let isAvailable = false
    var statusDescription: String { "AppKit fallback (not visible on Lock Screen)" }

    func promote(_ window: NSWindow, for screen: NSScreen) {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.orderFrontRegardless()
        LockClockLog.info("Using AppKit screenSaver level on \(screen.localizedName); SkyLight unavailable")
    }

    func showOverlaySpace() {}
    func hideOverlaySpace() {}
    func currentSpaceID() -> UInt64 { 0 }
}
