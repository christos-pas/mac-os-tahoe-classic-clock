import AppKit

final class DiagnosticsWindowController: NSWindowController, NSWindowDelegate {
    private weak var controller: LockClockController?
    private let textView = NSTextView()
    private let forceShowButton = NSButton(title: "Force Show Clock", target: nil, action: nil)
    private let forceHideButton = NSButton(title: "Force Hide Clock", target: nil, action: nil)
    private let loginItemButton = NSButton(title: "Enable Launch at Login", target: nil, action: nil)
    private let familyPopup = NSPopUpButton()
    private let weightPopup = NSPopUpButton()
    private let secondsCheckbox = NSButton(checkboxWithTitle: "Show seconds", target: nil, action: nil)
    private let sizeSlider = NSSlider()
    private let xSlider = NSSlider()
    private let ySlider = NSSlider()
    private let opacitySlider = NSSlider()
    private let colorWell = NSColorWell()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let xLabel = NSTextField(labelWithString: "")
    private let yLabel = NSTextField(labelWithString: "")
    private let opacityLabel = NSTextField(labelWithString: "")

    init(controller: LockClockController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lock Clock Diagnostics"
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)
        window.delegate = self
        buildUI()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        guard let controller else { return }
        let appearance = Settings.shared.appearance
        let snapshot = LockScreenDetector.sessionSnapshot()
            .sorted { $0.key < $1.key }
            .map { "  \($0.key) = \($0.value)" }
            .joined(separator: "\n")

        textView.string = """
        Lock Clock diagnostics
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Process: \(ProcessInfo.processInfo.processName) pid=\(ProcessInfo.processInfo.processIdentifier)
        Activation policy: accessory (LSUIElement)

        Current lock state: \(controller.diagnosticState.rawValue)
        Screen locked (CGSession): \(LockScreenDetector.isScreenLocked())
        On console: \(LockScreenDetector.isOnConsole())
        SkyLight: \(controller.windowManagerStatus)
        Current Space: \(controller.currentSpace)
        Launch at Login: \(LaunchAtLogin.status)

        Displays:
        \(controller.displaySummary)

        Clock:
          font=\(appearance.family.displayName)
          weight=\(appearance.weight.displayName)
          size=\(Int(appearance.size))
          opacity=\(String(format: "%.2f", appearance.opacity))
          seconds=\(appearance.showSeconds)
          x=\(String(format: "%.2f", appearance.placement.horizontalFraction))
          y=\(String(format: "%.2f", appearance.placement.verticalFraction))
          spaceLevel=\(appearance.skyLightSpaceLevel)

        CGSession:
        \(snapshot)
        """
        loginItemButton.title = LaunchAtLogin.isEnabled ? "Disable Launch at Login" : "Enable Launch at Login"
        familyPopup.selectItem(withTitle: appearance.family.displayName)
        weightPopup.selectItem(withTitle: appearance.weight.displayName)
        secondsCheckbox.state = appearance.showSeconds ? .on : .off
        sizeSlider.doubleValue = Double(appearance.size)
        xSlider.doubleValue = Double(appearance.placement.horizontalFraction)
        ySlider.doubleValue = Double(appearance.placement.verticalFraction)
        opacitySlider.doubleValue = Double(appearance.opacity)
        colorWell.color = appearance.color
        updateSliderLabels()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        familyPopup.addItems(withTitles: ClockFontFamily.allCases.map(\.displayName))
        weightPopup.addItems(withTitles: ClockFontWeight.allCases.map(\.displayName))
        familyPopup.target = self
        familyPopup.action = #selector(appearanceChanged)
        weightPopup.target = self
        weightPopup.action = #selector(appearanceChanged)
        secondsCheckbox.target = self
        secondsCheckbox.action = #selector(appearanceChanged)

        configure(sizeSlider, min: 60, max: 240)
        configure(xSlider, min: 0, max: 1)
        configure(ySlider, min: 0, max: 1)
        configure(opacitySlider, min: 0.2, max: 1)
        colorWell.target = self
        colorWell.action = #selector(appearanceChanged)

        forceShowButton.target = self
        forceShowButton.action = #selector(forceShow)
        forceHideButton.target = self
        forceHideButton.action = #selector(forceHide)
        loginItemButton.target = self
        loginItemButton.action = #selector(toggleLoginItem)

        let buttons = NSStackView(views: [forceShowButton, forceHideButton, loginItemButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let appearanceRow = NSStackView(views: [
            labeled("Font", familyPopup),
            labeled("Weight", weightPopup),
            labeled("Color", colorWell),
            secondsCheckbox
        ])
        appearanceRow.orientation = .horizontal
        appearanceRow.spacing = 16

        let sliders = NSStackView(views: [
            labeled("Size", sizeSlider, sizeLabel),
            labeled("X", xSlider, xLabel),
            labeled("Y", ySlider, yLabel),
            labeled("Opacity", opacitySlider, opacityLabel)
        ])
        sliders.orientation = .vertical
        sliders.spacing = 6

        let stack = NSStackView(views: [scroll, appearanceRow, sliders, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sliders.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func configure(_ slider: NSSlider, min: Double, max: Double) {
        slider.minValue = min
        slider.maxValue = max
        slider.target = self
        slider.action = #selector(appearanceChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
    }

    private func labeled(_ title: String, _ control: NSView, _ valueLabel: NSTextField? = nil) -> NSView {
        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.boldSystemFont(ofSize: 11)
        var views: [NSView] = [titleField, control]
        if let valueLabel {
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            valueLabel.alignment = .right
            valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
            views.append(valueLabel)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func updateSliderLabels() {
        sizeLabel.stringValue = "\(Int(sizeSlider.doubleValue))"
        xLabel.stringValue = String(format: "%.2f", xSlider.doubleValue)
        yLabel.stringValue = String(format: "%.2f", ySlider.doubleValue)
        opacityLabel.stringValue = String(format: "%.2f", opacitySlider.doubleValue)
    }

    @objc private func appearanceChanged() {
        var appearance = Settings.shared.appearance
        if let family = ClockFontFamily.allCases.first(where: { $0.displayName == familyPopup.titleOfSelectedItem }) {
            appearance.family = family
        }
        if let weight = ClockFontWeight.allCases.first(where: { $0.displayName == weightPopup.titleOfSelectedItem }) {
            appearance.weight = weight
        }
        appearance.showSeconds = secondsCheckbox.state == .on
        appearance.size = CGFloat(sizeSlider.doubleValue)
        appearance.placement.horizontalFraction = CGFloat(xSlider.doubleValue)
        appearance.placement.verticalFraction = CGFloat(ySlider.doubleValue)
        appearance.opacity = CGFloat(opacitySlider.doubleValue)
        appearance.color = colorWell.color
        Settings.shared.appearance = appearance
        Settings.shared.notifyChange()
        updateSliderLabels()
    }

    @objc private func forceShow() {
        Settings.shared.debugShowClockWhileUnlocked = true
        controller?.forceShowClock()
        reload()
    }

    @objc private func forceHide() {
        Settings.shared.debugShowClockWhileUnlocked = false
        controller?.forceHideClock()
        reload()
    }

    @objc private func toggleLoginItem() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        reload()
    }
}
