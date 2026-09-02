import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var clockEnabled: Bool
    @Published var launchAtLogin: Bool
    @Published var family: ClockFontFamily
    @Published var weight: ClockFontWeight
    @Published var size: Double
    @Published var colorPosition: Double
    @Published var opacity: Double
    @Published var showSeconds: Bool
    @Published var horizontalFraction: Double
    @Published var verticalFraction: Double

    private var suppressPersist = false
    private(set) var isWriting = false

    init() {
        let appearance = Settings.shared.appearance
        clockEnabled = Settings.shared.clockEnabled
        launchAtLogin = LaunchAtLogin.isEnabled
        family = appearance.family
        weight = appearance.weight
        size = Double(appearance.size)
        colorPosition = ColorSpectrum.position(for: appearance.color)
        opacity = Double(appearance.opacity)
        showSeconds = appearance.showSeconds
        horizontalFraction = Double(appearance.placement.horizontalFraction)
        verticalFraction = Double(appearance.placement.verticalFraction)
    }

    func reloadFromDefaults() {
        suppressPersist = true
        let appearance = Settings.shared.appearance
        clockEnabled = Settings.shared.clockEnabled
        launchAtLogin = LaunchAtLogin.isEnabled
        family = appearance.family
        weight = appearance.weight
        size = Double(appearance.size)
        colorPosition = ColorSpectrum.position(for: appearance.color)
        opacity = Double(appearance.opacity)
        showSeconds = appearance.showSeconds
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
        appearance.placement.horizontalFraction = CGFloat(horizontalFraction)
        appearance.placement.verticalFraction = CGFloat(verticalFraction)

        let enabledChanged = Settings.shared.clockEnabled != clockEnabled
        let loginChanged = LaunchAtLogin.isEnabled != launchAtLogin
        let appearanceChanged = !Self.sameAppearance(Settings.shared.appearance, appearance)
        guard enabledChanged || loginChanged || appearanceChanged else { return }

        isWriting = true
        Settings.shared.clockEnabled = clockEnabled
        LaunchAtLogin.setEnabled(launchAtLogin)
        Settings.shared.appearance = appearance
        Settings.shared.notifyChange()
        isWriting = false
    }

    func resetToDefaults() {
        suppressPersist = true
        let appearance = ClockAppearance.default
        clockEnabled = true
        family = appearance.family
        weight = appearance.weight
        size = Double(appearance.size)
        colorPosition = ColorSpectrum.position(for: appearance.color)
        opacity = Double(appearance.opacity)
        showSeconds = appearance.showSeconds
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
        appearance.placement.horizontalFraction = CGFloat(horizontalFraction)
        appearance.placement.verticalFraction = CGFloat(verticalFraction)
        return appearance
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
            Text("Restore the default font, size, color, opacity, and position? Open at Login is not changed.")
        }
        .onAppear {
            WallpaperImage.startWatching()
            wallpaper = WallpaperImage.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            wallpaper = WallpaperImage.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: WallpaperImage.didChangeNotification)) { _ in
            wallpaper = WallpaperImage.current()
        }
        .onChange(of: model.clockEnabled) { _, _ in model.persist() }
        .onChange(of: model.launchAtLogin) { _, _ in model.persist() }
        .onChange(of: model.family) { _, _ in model.persist() }
        .onChange(of: model.weight) { _, _ in model.persist() }
        .onChange(of: model.size) { _, _ in model.persist() }
        .onChange(of: model.colorPosition) { _, _ in model.persist() }
        .onChange(of: model.opacity) { _, _ in model.persist() }
        .onChange(of: model.showSeconds) { _, _ in model.persist() }
        .onChange(of: model.horizontalFraction) { _, _ in model.persist() }
        .onChange(of: model.verticalFraction) { _, _ in model.persist() }
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Show Lock Screen Clock", isOn: $model.clockEnabled)
            Toggle("Open at Login", isOn: $model.launchAtLogin)
            LockScreenPreview(
                appearance: model.liveAppearance,
                enabled: model.clockEnabled,
                wallpaper: wallpaper
            )
            Spacer(minLength: 0)
        }
    }

    private var rightPanel: some View {
        Form {
            Section("Type") {
                Picker("Font", selection: $model.family) {
                    ForEach(ClockFontFamily.allCases, id: \.self) { family in
                        Text(family.displayName).tag(family)
                    }
                }
                Picker("Weight", selection: $model.weight) {
                    ForEach(ClockFontWeight.allCases, id: \.self) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                }
                Toggle("Show seconds", isOn: $model.showSeconds)
            }
            .disabled(!model.clockEnabled)

            Section("Look") {
                ColorTrackSlider(position: $model.colorPosition)
                slider("Size", value: $model.size, range: 60...240, format: "%.0f")
                slider("Opacity", value: $model.opacity, range: 0.2...1, format: "%.2f")
            }
            .disabled(!model.clockEnabled)

            Section("Position") {
                slider("Horizontal", value: $model.horizontalFraction, range: 0...1, format: "%.2f")
                slider("Vertical", value: $model.verticalFraction, range: 0...1, format: "%.2f")
                Text("Horizontal 0.5 is centered. Vertical is measured from the top of the screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .disabled(!model.clockEnabled)

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
                ClockView(appearance: appearance, scale: scale)
                    .opacity(enabled ? 1 : 0.35)
                    .position(
                        x: geometry.size.width * appearance.placement.horizontalFraction,
                        y: geometry.size.height * appearance.placement.verticalFraction
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
