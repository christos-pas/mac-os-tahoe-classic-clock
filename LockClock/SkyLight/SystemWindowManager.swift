import AppKit

protocol SystemWindowManager: AnyObject {
    var isAvailable: Bool { get }
    var connectionID: Int32 { get }
    var spaceID: Int32 { get }
    var spaceLevel: Int32 { get }
    var statusDescription: String { get }

    func promote(_ window: NSWindow, for screen: NSScreen)
    func demote(_ window: NSWindow)
    func showOverlaySpace()
    func hideOverlaySpace()
    func currentSpaceID() -> UInt64
}

extension SystemWindowManager {
    func demote(_ window: NSWindow) {
        window.orderOut(nil)
    }
}
