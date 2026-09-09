import AppKit
import Foundation

struct ClockFontFamily: Hashable, RawRepresentable {
    let rawValue: String

    static let system = ClockFontFamily(rawValue: "system")

    static func lockScreen(_ font: AppleLockScreenClock.SystemClockFont) -> ClockFontFamily {
        ClockFontFamily(rawValue: "lockScreen.\(font.rawValue)")
    }

    static func installed(_ familyName: String) -> ClockFontFamily {
        ClockFontFamily(rawValue: "family.\(familyName)")
    }

    /// Clock Appearance options from System Settings, in system order.
    static var lockScreenMenuItems: [ClockFontFamily] {
        AppleLockScreenClock.SystemClockFont.allCases.map(lockScreen)
    }

    /// Installed families that can draw clock digits (excludes private / emoji / symbol faces).
    static var installedMenuItems: [ClockFontFamily] {
        cachedInstalledMenuItems
    }

    private static let cachedInstalledMenuItems: [ClockFontFamily] = {
        let lockScreenFamilies = Set(
            AppleLockScreenClock.SystemClockFont.allCases.map(\.fontFamily)
        )
        let excluded: Set<String> = [
            "Apple Color Emoji",
            "Apple Symbols",
            "Apple Braille",
            ".AppleSystemUIFont"
        ]
        return NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard !family.hasPrefix(".") else { return false }
                guard !excluded.contains(family) else { return false }
                guard !lockScreenFamilies.contains(family) else { return false }
                return supportsClockDigits(familyName: family)
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map(installed)
    }()

    init(rawValue: String) {
        self.rawValue = Self.migrateLegacyRawValue(rawValue)
    }

    var displayName: String {
        if self == .system { return "System" }
        if let lockScreenFont { return lockScreenFont.displayName }
        if let familyName = installedFamilyName { return familyName }
        return rawValue
    }

    var lockScreenFont: AppleLockScreenClock.SystemClockFont? {
        guard rawValue.hasPrefix("lockScreen.") else { return nil }
        let id = String(rawValue.dropFirst("lockScreen.".count))
        return AppleLockScreenClock.SystemClockFont(identifier: id)
    }

    var installedFamilyName: String? {
        guard rawValue.hasPrefix("family.") else { return nil }
        return String(rawValue.dropFirst("family.".count))
    }

    func previewFont(size: CGFloat = 13) -> NSFont {
        makeFont(weight: .regular, pointSize: size)
    }

    func makeFont(weight: ClockFontWeight, pointSize: CGFloat) -> NSFont {
        if let lockScreenFont {
            return AppleLockScreenClock.makeSystemFont(
                identifier: lockScreenFont.rawValue,
                weight: weight.systemWeightValue,
                pointSize: pointSize
            )
        }
        if self == .system {
            return NSFont.systemFont(ofSize: pointSize, weight: weight.nsWeight)
        }
        if let familyName = installedFamilyName {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: familyName,
                .traits: [NSFontDescriptor.TraitKey.weight: weight.nsWeight.rawValue]
            ])
            if let font = NSFont(descriptor: descriptor, size: pointSize) {
                return font
            }
            if let named = NSFont(name: familyName, size: pointSize) {
                return named
            }
        }
        return NSFont.systemFont(ofSize: pointSize, weight: weight.nsWeight)
    }

    private static func supportsClockDigits(familyName: String) -> Bool {
        let descriptor = NSFontDescriptor(fontAttributes: [.family: familyName])
        guard let font = NSFont(descriptor: descriptor, size: 24) else { return false }
        var characters = Array("0123456789".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let ok = CTFontGetGlyphsForCharacters(font as CTFont, &characters, &glyphs, characters.count)
        return ok && glyphs.allSatisfy { $0 != 0 }
    }

    private static func migrateLegacyRawValue(_ raw: String) -> String {
        switch raw {
        case "helveticaNeue":
            return installed("Helvetica Neue").rawValue
        case "sfPro":
            return installed("SF Pro").rawValue
        case "sfCompact":
            return installed("SF Compact").rawValue
        default:
            return raw
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

    /// Approximate mapping onto Apple's 0…1000 lock-screen weight scale.
    var systemWeightValue: Int {
        switch self {
        case .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
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
    var matchSystemClock: Bool
    /// Populated when `matchSystemClock` is resolved for rendering; not persisted.
    var systemFontIdentifier: String?
    var systemFontWeight: Int?

    static let `default` = ClockAppearance(
        family: .system,
        weight: .regular,
        size: SystemClockLayout.defaultTimePointSize,
        color: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        opacity: 0.70,
        showSeconds: false,
        placement: SystemClockLayout.defaultAppearancePlacement,
        skyLightSpaceLevel: 400,
        matchSystemClock: true,
        systemFontIdentifier: nil,
        systemFontWeight: nil
    )

    func resolved(on screen: NSScreen) -> ClockAppearance {
        AppleLockScreenClock.matchedAppearance(from: self, on: screen)
    }

    func makeFont(pointSize: CGFloat? = nil) -> NSFont {
        let pointSize = pointSize ?? size
        if matchSystemClock, let prefs = AppleLockScreenClock.readPreferences() {
            return AppleLockScreenClock.makeSystemFont(
                identifier: prefs.fontIdentifier,
                weight: prefs.fontWeight,
                pointSize: pointSize
            )
        }
        return family.makeFont(weight: weight, pointSize: pointSize)
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
        static let matchSystemClock = "clock.matchSystemClock"
    }

    private init() {}

    static var shouldOpenSettingsOnLaunch: Bool {
        if ProcessInfo.processInfo.arguments.contains("--settings") { return true }
        if isDebugMode { return false }
        return !LaunchAtLogin.isEnabled
    }

    func notifyChange() {
        onChange?()
        NotificationCenter.default.post(name: .lockClockSettingsDidChange, object: nil)
    }

    private func loadAppearance() -> ClockAppearance {
        var appearance = ClockAppearance.default
        if let raw = defaults.string(forKey: Keys.fontFamily) {
            appearance.family = ClockFontFamily(rawValue: raw)
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
        if defaults.object(forKey: Keys.matchSystemClock) != nil {
            appearance.matchSystemClock = defaults.bool(forKey: Keys.matchSystemClock)
        }
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
        defaults.set(appearance.matchSystemClock, forKey: Keys.matchSystemClock)
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
