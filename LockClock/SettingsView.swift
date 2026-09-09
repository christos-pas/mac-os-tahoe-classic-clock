import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var launchAtLogin: Bool
    @Published var family: ClockFontFamily
    @Published var weight: ClockFontWeight
    @Published var size: Double
    @Published var colorPosition: Double
    @Published var opacity: Double
    @Published var showSeconds: Bool
    @Published var matchSystemClock: Bool
    @Published var horizontalFraction: Double
    @Published var verticalFraction: Double

    private var suppressPersist = false
    private(set) var isWriting = false

    init() {
        let appearance = Settings.shared.appearance
        launchAtLogin = LaunchAtLogin.isEnabled
        family = appearance.family
        weight = appearance.weight
        size = Double(appearance.size)
        colorPosition = ColorSpectrum.position(for: appearance.color)
        opacity = Double(appearance.opacity)
        showSeconds = appearance.showSeconds
        matchSystemClock = appearance.matchSystemClock
        horizontalFraction = Double(appearance.placement.horizontalFraction)
        verticalFraction = Double(appearance.placement.verticalFraction)
    }

    func reloadFromDefaults() {
        suppressPersist = true
        let appearance = Settings.shared.appearance
        launchAtLogin = LaunchAtLogin.isEnabled
        family = appearance.family
        weight = appearance.weight
        size = Double(appearance.size)
        colorPosition = ColorSpectrum.position(for: appearance.color)
        opacity = Double(appearance.opacity)
        showSeconds = appearance.showSeconds
        matchSystemClock = appearance.matchSystemClock
        horizontalFraction = Double(appearance.placement.horizontalFraction)
        verticalFraction = Double(appearance.placement.verticalFraction)
        suppressPersist = false
    }

    func persist() {
        guard !suppressPersist else { return }

        var appearance = Settings.shared.appearance
        appearance.family = family
        appearance.weight = weight
        appearance.size = CGFloat(size)
        appearance.color = ColorSpectrum.nsColor(at: colorPosition)
        appearance.opacity = CGFloat(opacity)
        appearance.showSeconds = showSeconds
        appearance.matchSystemClock = matchSystemClock
        appearance.placement.horizontalFraction = CGFloat(horizontalFraction)
        appearance.placement.verticalFraction = CGFloat(verticalFraction)

        let loginChanged = LaunchAtLogin.isEnabled != launchAtLogin
        let appearanceChanged = !Self.sameAppearance(Settings.shared.appearance, appearance)
        guard loginChanged || appearanceChanged else { return }

        isWriting = true
        LaunchAtLogin.setEnabled(launchAtLogin)
        Settings.shared.appearance = appearance
        Settings.shared.notifyChange()
        isWriting = false
    }

    func resetToDefaults() {
        suppressPersist = true
        let appearance = ClockAppearance.default
        family = appearance.family
        weight = appearance.weight
        size = Double(appearance.size)
        colorPosition = ColorSpectrum.position(for: appearance.color)
        opacity = Double(appearance.opacity)
        showSeconds = appearance.showSeconds
        matchSystemClock = appearance.matchSystemClock
        horizontalFraction = Double(appearance.placement.horizontalFraction)
        verticalFraction = Double(appearance.placement.verticalFraction)
        suppressPersist = false
        persist()
    }

    private static func sameAppearance(_ lhs: ClockAppearance, _ rhs: ClockAppearance) -> Bool {
        lhs.family == rhs.family
            && lhs.weight == rhs.weight
            && abs(lhs.size - rhs.size) < 0.5
            && abs(lhs.opacity - rhs.opacity) < 0.01
            && lhs.showSeconds == rhs.showSeconds
            && lhs.matchSystemClock == rhs.matchSystemClock
            && abs(lhs.placement.horizontalFraction - rhs.placement.horizontalFraction) < 0.001
            && abs(lhs.placement.verticalFraction - rhs.placement.verticalFraction) < 0.001
            && colorsMatch(lhs.color, rhs.color)
    }

    private static func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = lhs.usingColorSpace(.sRGB) ?? lhs
        let right = rhs.usingColorSpace(.sRGB) ?? rhs
        return abs(left.redComponent - right.redComponent) < 0.01
            && abs(left.greenComponent - right.greenComponent) < 0.01
            && abs(left.blueComponent - right.blueComponent) < 0.01
    }

    var liveAppearance: ClockAppearance {
        var appearance = Settings.shared.appearance
        appearance.family = family
        appearance.weight = weight
        appearance.size = CGFloat(size)
        appearance.color = ColorSpectrum.nsColor(at: colorPosition)
        appearance.opacity = CGFloat(opacity)
        appearance.showSeconds = showSeconds
        appearance.matchSystemClock = matchSystemClock
        appearance.placement.horizontalFraction = CGFloat(horizontalFraction)
        appearance.placement.verticalFraction = CGFloat(verticalFraction)
        guard matchSystemClock, let screen = NSScreen.main ?? NSScreen.screens.first else {
            return appearance
        }
        return appearance.resolved(on: screen)
    }
}

enum ColorSpectrum {
    static let stops: [(position: Double, red: Double, green: Double, blue: Double)] = [
        (0.00, 1.00, 1.00, 1.00),
        (0.12, 1.00, 0.92, 0.80),
        (0.24, 1.00, 0.84, 0.40),
        (0.36, 1.00, 0.55, 0.20),
        (0.48, 1.00, 0.30, 0.30),
        (0.60, 0.75, 0.40, 1.00),
        (0.72, 0.35, 0.60, 1.00),
        (0.84, 0.30, 0.90, 0.95),
        (1.00, 0.40, 0.90, 0.50)
    ]

    static var gradientColors: [Color] {
        stops.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    static func nsColor(at position: Double) -> NSColor {
        let rgb = components(at: position)
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    static func color(at position: Double) -> Color {
        let rgb = components(at: position)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func position(for color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let target = (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        var bestPosition = 0.0
        var bestDistance = Double.greatestFiniteMagnitude
        for step in 0...100 {
            let position = Double(step) / 100
            let sample = components(at: position)
            let distance = abs(sample.red - target.0) + abs(sample.green - target.1) + abs(sample.blue - target.2)
            if distance < bestDistance {
                bestDistance = distance
                bestPosition = position
            }
        }
        return bestPosition
    }

    private static func components(at position: Double) -> (red: Double, green: Double, blue: Double) {
        let clamped = min(1, max(0, position))
        if let exact = stops.first(where: { abs($0.position - clamped) < 0.0001 }) {
            return (exact.red, exact.green, exact.blue)
        }
        let nextIndex = stops.firstIndex(where: { $0.position >= clamped }) ?? (stops.count - 1)
        let previousIndex = max(0, nextIndex - 1)
        let start = stops[previousIndex]
        let end = stops[nextIndex]
        let span = max(end.position - start.position, 0.0001)
        let t = (clamped - start.position) / span
        return (
            start.red + (end.red - start.red) * t,
            start.green + (end.green - start.green) * t,
            start.blue + (end.blue - start.blue) * t
        )
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmReset = false
    @State private var showAppleClockAlert = false
    @State private var appleLargeClockOn = AppleLockScreenClock.isLargeClockEnabled
    @State private var wallpaper: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            leftPanel
                .frame(width: 360)
            rightPanel
                .frame(minWidth: 380, maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 820, height: 560)
        .alert("Set Defaults", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Set Defaults") {
                model.resetToDefaults()
            }
        } message: {
            Text("Restore the default font, size, color, opacity, and position? Launch at Login is not changed.")
        }
        .alert("Turn Off Apple's Lock Screen Clock", isPresented: $showAppleClockAlert) {
            Button("Open System Settings") {
                AppleLockScreenClock.openClockAppearanceSettings()
            }
            Button("Enable Anyway") {
                model.launchAtLogin = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                """
                Apple’s large Lock Screen clock is still on. In System Settings → Wallpaper → Clock Appearance, set Show large clock to Never. Then run sudo diskutil apfs updatePreboot / in Terminal and restart so the change applies everywhere (FileVault, boot, and wake).
                """
            )
        }
        .onAppear {
            refreshAppleClockState()
            WallpaperImage.startWatching()
            wallpaper = WallpaperImage.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAppleClockState()
            Settings.shared.notifyChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppleLockScreenClock.preferencesDidChangeNotification)) { _ in
            refreshAppleClockState()
            Settings.shared.notifyChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            wallpaper = WallpaperImage.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: WallpaperImage.didChangeNotification)) { _ in
            wallpaper = WallpaperImage.current()
        }
        .onChange(of: model.launchAtLogin) { _, _ in model.persist() }
        .onChange(of: model.family) { _, _ in model.persist() }
        .onChange(of: model.weight) { _, _ in model.persist() }
        .onChange(of: model.size) { _, _ in model.persist() }
        .onChange(of: model.colorPosition) { _, _ in model.persist() }
        .onChange(of: model.opacity) { _, _ in model.persist() }
        .onChange(of: model.showSeconds) { _, _ in model.persist() }
        .onChange(of: model.matchSystemClock) { _, _ in model.persist() }
        .onChange(of: model.horizontalFraction) { _, _ in model.persist() }
        .onChange(of: model.verticalFraction) { _, _ in model.persist() }
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(
                "Enable Classic Lock Screen Clock (Launch at Login)",
                isOn: enableToggleBinding
            )
            appleClockSection
            LockScreenPreview(
                appearance: model.liveAppearance,
                enabled: model.launchAtLogin,
                wallpaper: wallpaper
            )
            Spacer(minLength: 0)
        }
    }

    private var enableToggleBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { newValue in
                if newValue, !model.matchSystemClock, AppleLockScreenClock.isLargeClockEnabled {
                    showAppleClockAlert = true
                    return
                }
                model.launchAtLogin = newValue
            }
        )
    }

    private var appleClockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appleLargeClockOn, !model.matchSystemClock {
                Label {
                    Text("Apple's large Lock Screen clock is on. Turn it off, or enable Match System Clock to draw on top.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(.orange)
            } else if model.matchSystemClock {
                Text("Match System Clock draws a solid clock aligned with Apple's. Apple's clock can stay on underneath.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.matchSystemClock {
                Text("System clock: \(AppleLockScreenClock.systemFontSummary())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Open Clock Appearance in System Settings…") {
                AppleLockScreenClock.openClockAppearanceSettings()
            }
            .controlSize(.small)
        }
    }

    private func refreshAppleClockState() {
        appleLargeClockOn = AppleLockScreenClock.isLargeClockEnabled
    }

    private var rightPanel: some View {
        Form {
            Section("Type") {
                Picker("Font", selection: $model.family) {
                    ForEach(ClockFontFamily.lockScreenMenuItems, id: \.self) { family in
                        Text(family.displayName)
                            .font(Font(family.previewFont()))
                            .tag(family)
                    }
                    Divider()
                    Text(ClockFontFamily.system.displayName)
                        .font(Font(ClockFontFamily.system.previewFont()))
                        .tag(ClockFontFamily.system)
                    ForEach(ClockFontFamily.installedMenuItems, id: \.self) { family in
                        Text(family.displayName)
                            .font(Font(family.previewFont()))
                            .tag(family)
                    }
                }
                Picker("Weight", selection: $model.weight) {
                    ForEach(ClockFontWeight.allCases, id: \.self) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                }
                Toggle("Show seconds", isOn: $model.showSeconds)
            }
            .disabled(!model.launchAtLogin || model.matchSystemClock)

            Section("System") {
                Toggle("Match System Clock", isOn: $model.matchSystemClock)
                if model.matchSystemClock {
                    Text("Uses font, weight, size, and position from Clock Appearance in System Settings. Drawn solid white on top of Apple's clock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!model.launchAtLogin)

            Section("Look") {
                ColorTrackSlider(position: $model.colorPosition)
                slider("Size", value: $model.size, range: 60...240, format: "%.0f")
                slider("Opacity", value: $model.opacity, range: 0.2...1, format: "%.2f")
            }
            .disabled(!model.launchAtLogin || model.matchSystemClock)

            Section("Position") {
                slider("Horizontal", value: $model.horizontalFraction, range: 0...1, format: "%.2f")
                slider("Vertical", value: $model.verticalFraction, range: 0...1, format: "%.2f")
            }
            .disabled(!model.launchAtLogin || model.matchSystemClock)

            Section {
                Button("Set Defaults…") {
                    confirmReset = true
                }
            }
        }
        .formStyle(.grouped)
        .padding(-8)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct ColorTrackSlider: View {
    @Binding var position: Double

    var body: some View {
        HStack {
            Text("Color")
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let thumb = 16.0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: ColorSpectrum.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 6)
                    Circle()
                        .fill(ColorSpectrum.color(at: position))
                        .frame(width: thumb, height: thumb)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .offset(x: CGFloat(position) * (width - thumb))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let x = min(max(value.location.x, 0), width)
                        position = x / width
                    }
                )
            }
            .frame(height: 22)
            Circle()
                .fill(ColorSpectrum.color(at: position))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
        }
    }
}

struct LockScreenPreview: View {
    var appearance: ClockAppearance
    var enabled: Bool
    var wallpaper: NSImage?

    @State private var clockSize: CGSize?

    private var screenFrame: NSRect {
        (NSScreen.main ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
    }

    private var aspectRatio: CGFloat {
        guard screenFrame.height > 0 else { return 16 / 10 }
        return screenFrame.width / screenFrame.height
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / max(screenFrame.width, 1)
            ZStack {
                previewBackground
                if let clockSize {
                    ClockView(appearance: appearance, scale: scale)
                        .opacity(enabled ? 1 : 0.35)
                        .position(
                            SystemClockLayout.previewCenter(
                                viewSize: clockSize,
                                appearance: appearance,
                                previewSize: geometry.size,
                                screenHeight: screenFrame.height
                            )
                        )
                }
                ClockView(appearance: appearance, scale: scale)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { clockSize = proxy.size }
                                .onChange(of: proxy.size) { _, size in clockSize = size }
                        }
                    )
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var previewBackground: some View {
        if let wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.black
        }
    }
}
