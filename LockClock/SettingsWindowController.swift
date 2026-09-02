import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model = SettingsModel()
    private var observer: NSObjectProtocol?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lock Clock Settings"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
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
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
