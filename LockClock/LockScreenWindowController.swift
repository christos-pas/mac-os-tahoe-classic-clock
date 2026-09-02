import AppKit
import SwiftUI

final class LockScreenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class LockScreenWindowController: NSWindowController {
    let screenID: CGDirectDisplayID
    private(set) var screenName: String
    private var hostingView: NSHostingView<ClockView>?

    init(screen: NSScreen) {
        self.screenID = screen.displayID
        self.screenName = screen.localizedName

        let window = LockScreenWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.animationBehavior = .none
        window.collectionBehavior = [
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
            .fullScreenAuxiliary,
            .transient
        ]
        window.canBecomeVisibleWithoutLogin = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.sharingType = .none
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = false

        super.init(window: window)
        applyAppearance(Settings.shared.appearance, on: screen)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyAppearance(_ appearance: ClockAppearance, on screen: NSScreen) {
        screenName = screen.localizedName
        let view = ClockView(appearance: appearance)
        let hosting = NSHostingView(rootView: view)
        hosting.safeAreaRegions = []
        window?.contentView = hosting
        hostingView = hosting
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let frame = Self.frame(for: size, placement: appearance.placement, clockSize: appearance.size, on: screen)
        window?.setFrame(frame, display: true)
    }

    func show(using manager: SystemWindowManager, on screen: NSScreen) {
        guard let window else { return }
        applyAppearance(Settings.shared.appearance, on: screen)
        window.orderFrontRegardless()
        manager.promote(window, for: screen)
        LockClockLog.info("Clock visible")
    }

    func hide(using manager: SystemWindowManager) {
        guard let window else { return }
        manager.demote(window)
        LockClockLog.info("Clock hidden")
    }

    var diagnosticFrame: String {
        guard let window else { return "none" }
        return NSStringFromRect(window.frame)
    }

    var diagnosticLevel: String {
        guard let window else { return "none" }
        return String(window.level.rawValue)
    }

    private static func frame(
        for size: NSSize,
        placement: ClockPlacement,
        clockSize: CGFloat,
        on screen: NSScreen
    ) -> NSRect {
        let width = max(size.width, 80)
        let height = max(size.height, 40)
        let x = screen.frame.minX + screen.frame.width * placement.horizontalFraction - width / 2
        let yFromTop = screen.frame.height * placement.verticalFraction
        // Keep the time centered on the configured point; the date sits above it.
        let dateOffset = clockSize * 0.15
        let y = screen.frame.maxY - yFromTop - height / 2 + dateOffset
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
