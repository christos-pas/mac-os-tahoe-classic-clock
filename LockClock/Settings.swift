import AppKit
import Foundation

enum ClockFontFamily: String, CaseIterable {
    case system
    case helveticaNeue
    case sfPro
    case sfCompact

    var displayName: String {
        switch self {
        case .system: return "System"
        case .helveticaNeue: return "Helvetica Neue"
        case .sfPro: return "SF Pro"
        case .sfCompact: return "SF Compact"
        }
    }
}

enum ClockFontWeight: String, CaseIterable {
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold

    var displayName: String {
        rawValue.capitalized
    }

    var nsWeight: NSFont.Weight {
        switch self {
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

struct ClockPlacement: Equatable {
    /// 0 is the leading edge, 0.5 is centered.
    var horizontalFraction: CGFloat
    /// 0 is the top of the screen, 1 is the bottom.
    var verticalFraction: CGFloat
}

struct ClockAppearance: Equatable {
    var family: ClockFontFamily
    var weight: ClockFontWeight
    var size: CGFloat
    var color: NSColor
    var opacity: CGFloat
    var showSeconds: Bool
    var placement: ClockPlacement
    var skyLightSpaceLevel: Int32

    static let `default` = ClockAppearance(
        family: .system,
        weight: .regular,
        size: 125,
        color: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        opacity: 0.70,
        showSeconds: false,
        placement: ClockPlacement(horizontalFraction: 0.50, verticalFraction: 0.20),
        skyLightSpaceLevel: 400
    )

    func makeFont(pointSize: CGFloat? = nil) -> NSFont {
        let pointSize = pointSize ?? size
        let fallback = NSFont.systemFont(ofSize: pointSize, weight: weight.nsWeight)
        let named: NSFont?
        switch family {
        case .system:
            return fallback
        case .helveticaNeue:
            named = NSFont(name: "Helvetica Neue", size: pointSize)
        case .sfPro:
            named = NSFont(name: "SF Pro Display", size: pointSize) ?? NSFont(name: "SF Pro", size: pointSize)
        case .sfCompact:
            named = NSFont(name: "SF Compact Display", size: pointSize) ?? NSFont(name: "SF Compact", size: pointSize)
        }
        guard let named else { return fallback }
        let traits: [NSFontDescriptor.TraitKey: Any] = [.weight: weight.nsWeight.rawValue]
        let descriptor = named.fontDescriptor.addingAttributes([.traits: traits])
        return NSFont(descriptor: descriptor, size: pointSize) ?? named
    }
}

final class Settings {
    static let shared = Settings()

    static var isDebugMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--debug")
            || ProcessInfo.processInfo.environment["LOCKCLOCK_DEBUG"] == "1"
            || UserDefaults.standard.bool(forKey: Keys.debugMode)
    }

    static var forceShowClock: Bool {
        ProcessInfo.processInfo.arguments.contains("--force-clock")
    }

    var debugLoggingEnabled: Bool {
        get { defaults.bool(forKey: Keys.debugLogging) }
        set { defaults.set(newValue, forKey: Keys.debugLogging) }
    }

    var debugShowClockWhileUnlocked: Bool {
        get { defaults.bool(forKey: Keys.debugShowClockWhileUnlocked) }
        set { defaults.set(newValue, forKey: Keys.debugShowClockWhileUnlocked) }
    }

    var hasAutoRegisteredLoginItem: Bool {
        get { defaults.bool(forKey: Keys.loginItemAutoRegistered) }
        set { defaults.set(newValue, forKey: Keys.loginItemAutoRegistered) }
    }

    /// When false the app stays running but never shows the lock-screen clock.
    var clockEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.clockEnabled) == nil { return true }
            return defaults.bool(forKey: Keys.clockEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.clockEnabled) }
    }

    var appearance: ClockAppearance {
        get { loadAppearance() }
        set { saveAppearance(newValue) }
    }

    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let debugMode = "debugMode"
        static let debugLogging = "debugLogging"
        static let debugShowClockWhileUnlocked = "debugShowClockWhileUnlocked"
        static let loginItemAutoRegistered = "loginItemAutoRegistered"
        static let clockEnabled = "clock.enabled"
        static let fontFamily = "clock.fontFamily"
        static let fontWeight = "clock.fontWeight"
        static let fontSize = "clock.fontSize"
        static let colorRed = "clock.colorRed"
        static let colorGreen = "clock.colorGreen"
        static let colorBlue = "clock.colorBlue"
        static let opacity = "clock.opacity"
        static let showSeconds = "clock.showSeconds"
        static let horizontalFraction = "clock.horizontalFraction"
        static let verticalFraction = "clock.verticalFraction"
        static let skyLightSpaceLevel = "clock.skyLightSpaceLevel"
    }

    private init() {}

    static var shouldOpenSettingsOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--settings")
    }

    func notifyChange() {
        onChange?()
        NotificationCenter.default.post(name: .lockClockSettingsDidChange, object: nil)
    }

    private func loadAppearance() -> ClockAppearance {
        var appearance = ClockAppearance.default
        if let raw = defaults.string(forKey: Keys.fontFamily),
           let family = ClockFontFamily(rawValue: raw) {
            appearance.family = family
        }
        if let raw = defaults.string(forKey: Keys.fontWeight),
           let weight = ClockFontWeight(rawValue: raw) {
            appearance.weight = weight
        }
        if defaults.object(forKey: Keys.fontSize) != nil {
            appearance.size = CGFloat(defaults.double(forKey: Keys.fontSize))
        }
        if defaults.object(forKey: Keys.opacity) != nil {
            appearance.opacity = CGFloat(defaults.double(forKey: Keys.opacity))
        }
        appearance.showSeconds = defaults.bool(forKey: Keys.showSeconds)
        if defaults.object(forKey: Keys.horizontalFraction) != nil {
            appearance.placement.horizontalFraction = CGFloat(defaults.double(forKey: Keys.horizontalFraction))
        }
        if defaults.object(forKey: Keys.verticalFraction) != nil {
            appearance.placement.verticalFraction = CGFloat(defaults.double(forKey: Keys.verticalFraction))
        }
        if defaults.object(forKey: Keys.skyLightSpaceLevel) != nil {
            appearance.skyLightSpaceLevel = Int32(defaults.integer(forKey: Keys.skyLightSpaceLevel))
        }
        if defaults.object(forKey: Keys.colorRed) != nil {
            appearance.color = NSColor(
                srgbRed: CGFloat(defaults.double(forKey: Keys.colorRed)),
                green: CGFloat(defaults.double(forKey: Keys.colorGreen)),
                blue: CGFloat(defaults.double(forKey: Keys.colorBlue)),
                alpha: 1
            )
        }
        return appearance
    }

    private func saveAppearance(_ appearance: ClockAppearance) {
        defaults.set(appearance.family.rawValue, forKey: Keys.fontFamily)
        defaults.set(appearance.weight.rawValue, forKey: Keys.fontWeight)
        defaults.set(Double(appearance.size), forKey: Keys.fontSize)
        defaults.set(Double(appearance.opacity), forKey: Keys.opacity)
        defaults.set(appearance.showSeconds, forKey: Keys.showSeconds)
        defaults.set(Double(appearance.placement.horizontalFraction), forKey: Keys.horizontalFraction)
        defaults.set(Double(appearance.placement.verticalFraction), forKey: Keys.verticalFraction)
        defaults.set(Int(appearance.skyLightSpaceLevel), forKey: Keys.skyLightSpaceLevel)
        let rgb = appearance.color.usingColorSpace(.sRGB) ?? appearance.color
        defaults.set(Double(rgb.redComponent), forKey: Keys.colorRed)
        defaults.set(Double(rgb.greenComponent), forKey: Keys.colorGreen)
        defaults.set(Double(rgb.blueComponent), forKey: Keys.colorBlue)
    }
}

extension Notification.Name {
    static let lockClockSettingsDidChange = Notification.Name("LockClockSettingsDidChange")
}
