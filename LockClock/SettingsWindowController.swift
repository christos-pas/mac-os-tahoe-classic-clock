import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = NSSize(width: 820, height: 560)

    private let model = SettingsModel()
    private var observer: NSObjectProtocol?

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lock Clock Settings"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.contentMinSize = Self.contentSize
        // Prevent SwiftUI's ideal size (e.g. long font names) from growing the window
        // past the screen after we center it.
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = []
        super.init(window: window)
        window.delegate = self
        window.contentViewController = hosting
        window.setContentSize(Self.contentSize)
        observer = NotificationCenter.default.addObserver(
            forName: .lockClockSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.model.isWriting else { return }
            self.model.reloadFromDefaults()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show() {
        model.reloadFromDefaults()
        guard let window else { return }
        window.setContentSize(Self.contentSize)
        centerOnVisibleScreen(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Hosting view finishes layout after the first display pass.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            window.setContentSize(Self.contentSize)
            self.centerOnVisibleScreen(window)
        }
    }

    /// Centers on the screen under the mouse (fallback: main), inside `visibleFrame`.
    private func centerOnVisibleScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            window.center()
            return
        }

        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.contentSize)).size
        frame.origin.x = visible.origin.x + (visible.width - frame.width) / 2
        frame.origin.y = visible.origin.y + (visible.height - frame.height) / 2
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        window.setFrame(frame, display: true)
    }
}
