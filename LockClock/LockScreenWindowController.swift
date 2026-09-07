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
        let resolved = appearance.resolved(on: screen)

        let measureHosting = NSHostingView(rootView: ClockView(appearance: resolved))
        measureHosting.layoutSubtreeIfNeeded()
        let size = measureHosting.fittingSize
        let frame = SystemClockLayout.windowFrame(
            viewSize: size,
            appearance: resolved,
            on: screen
        )
        window?.setFrame(frame, display: true)

        let context = backdropContext(
            for: resolved,
            on: screen,
            windowFrame: window?.frame ?? frame
        )
        let view = ClockView(appearance: resolved, backdropContext: context)
        let hosting = NSHostingView(rootView: view)
        hosting.safeAreaRegions = []
        hosting.wantsLayer = true
        if resolved.backdropBlur {
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
        }
        window?.contentView = hosting
        hostingView = hosting
    }

    private func backdropContext(
        for appearance: ClockAppearance,
        on screen: NSScreen,
        windowFrame: NSRect?
    ) -> ClockBackdropContext? {
        guard appearance.backdropBlur, let windowFrame else { return nil }
        guard let wallpaper = WallpaperImage.current(for: screen) else {
            LockClockLog.info("Backdrop blur: no lock-screen wallpaper for \(screen.localizedName)")
            return nil
        }
        return ClockBackdropContext(
            wallpaper: wallpaper,
            screenFrame: screen.frame,
            windowFrame: windowFrame
        )
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
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
