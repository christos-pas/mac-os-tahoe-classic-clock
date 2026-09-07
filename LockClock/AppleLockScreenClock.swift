import AppKit
import Foundation

/// Reads Apple's lock-screen clock settings and maps them to Lock Clock appearance.
enum AppleLockScreenClock {
    static let clockAppearanceSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension?ClockAppearance"
    )!

    private static let preferencesDomain = "com.apple.loginwindow" as CFString
    private static let loginWindowPreferencesURL = URL(
        fileURLWithPath: "/Library/Preferences/com.apple.loginwindow.plist"
    )

    static let preferencesDidChangeNotification = Notification.Name("LockClockSystemClockPreferencesDidChange")

    /// Known Clock Appearance font identifiers on macOS Tahoe (Wallpaper settings).
    enum SystemClockFont: String, CaseIterable {
        case rounded
        case classic
        case flipup
        case newYork
        case stencil

        init?(identifier: String) {
            let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = Self(rawValue: normalized) {
                self = match
                return
            }
            switch normalized.lowercased() {
            case "newyork", "new york":
                self = .newYork
            default:
                return nil
            }
        }

        var displayName: String {
            switch self {
            case .rounded: return "Rounded"
            case .classic: return "Classic"
            case .flipup: return "Flip Up"
            case .newYork: return "New York"
            case .stencil: return "Stencil"
            }
        }

        var fontFamily: String {
            switch self {
            case .rounded:
                return ".SF Rail Rounded Numeric"
            case .classic:
                return ".SF Soft Numeric"
            case .flipup:
                return ".SF Soft Numeric"
            case .newYork:
                return ".New York Soft Numeric"
            case .stencil:
                return ".SF Stencil Numeric"
            }
        }
    }

    /// When `true`, Apple's large lock-screen clock is enabled and conflicts with Lock Clock.
    /// Missing preference defaults to enabled, matching a fresh macOS install.
    static var isLargeClockEnabled: Bool {
        isLargeClockEnabledValue ?? true
    }

    /// `nil` when the system preference could not be read.
    static var isLargeClockEnabledValue: Bool? {
        guard let prefs = readPreferences() else { return nil }
        return prefs.usesLargeDateTime
    }

    struct Preferences: Equatable {
        var fontIdentifier: String
        var fontWeight: Int
        var usesLargeDateTime: Bool

        var systemFont: SystemClockFont? {
            SystemClockFont(identifier: fontIdentifier)
        }
    }

    static func readPreferences() -> Preferences? {
        synchronizePreferences()

        let identifier = preferenceString(forKey: "ClockFontIdentifier")
        let weight = preferenceInt(forKey: "ClockFontWeight")
        let usesLarge = preferenceBool(forKey: "UsesLargeDateTime")

        guard let identifier else {
            LockClockLog.info("System clock prefs: ClockFontIdentifier missing")
            return nil
        }

        let prefs = Preferences(
            fontIdentifier: identifier,
            fontWeight: weight ?? 400,
            usesLargeDateTime: usesLarge ?? true
        )
        LockClockLog.info(
            "System clock prefs: font=\(prefs.fontIdentifier) weight=\(prefs.fontWeight) large=\(prefs.usesLargeDateTime)"
        )
        return prefs
    }

    static func startWatchingPreferences() {
        LoginWindowPreferencesMonitor.shared.start()
    }

    /// Solid clock aligned with Apple's large lock-screen clock on Tahoe.
    static func matchedAppearance(from custom: ClockAppearance, on screen: NSScreen) -> ClockAppearance {
        guard custom.matchSystemClock else { return custom }
        guard let prefs = readPreferences() else { return custom }
        let layout = SystemClockLayout.metrics(for: screen)
        var appearance = custom
        appearance.size = layout.timePointSize
        appearance.opacity = 1.0
        appearance.color = .white
        appearance.showSeconds = false
        appearance.backdropBlur = false
        appearance.placement = layout.clockPlacement()
        appearance.systemFontIdentifier = prefs.fontIdentifier
        appearance.systemFontWeight = prefs.fontWeight
        return appearance
    }

    static func makeSystemFont(identifier: String, weight: Int, pointSize: CGFloat) -> NSFont {
        let font = SystemClockFont(identifier: identifier)
        let family = font?.fontFamily ?? SystemClockFont.rounded.fontFamily
        if font == nil {
            LockClockLog.info("System clock font: unknown identifier '\(identifier)', using Rounded")
        }
        let traitWeight = fontTraitWeight(fromSystemWeight: weight)
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: traitWeight]
        ])
        return NSFont(descriptor: descriptor, size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: NSFont.Weight(traitWeight))
    }

    static func systemFontSummary() -> String {
        guard let prefs = readPreferences() else { return "unavailable" }
        let name = prefs.systemFont?.displayName ?? prefs.fontIdentifier
        return "\(name), weight \(prefs.fontWeight)"
    }

    @discardableResult
    static func openClockAppearanceSettings() -> Bool {
        NSWorkspace.shared.open(clockAppearanceSettingsURL)
    }

    // MARK: - Preference I/O

    private static func synchronizePreferences() {
        _ = CFPreferencesAppSynchronize(preferencesDomain)
    }

    private static func preferenceString(forKey key: String) -> String? {
        if let value = copyPreferenceValue(forKey: key) {
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return plistFallback()[key] as? String
    }

    private static func preferenceInt(forKey key: String) -> Int? {
        if let value = copyPreferenceValue(forKey: key) {
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String, let int = Int(string) { return int }
        }
        if let number = plistFallback()[key] as? NSNumber { return number.intValue }
        if let int = plistFallback()[key] as? Int { return int }
        return nil
    }

    private static func preferenceBool(forKey key: String) -> Bool? {
        if let value = copyPreferenceValue(forKey: key) {
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
        }
        if let bool = plistFallback()[key] as? Bool { return bool }
        if let number = plistFallback()[key] as? NSNumber { return number.boolValue }
        return nil
    }

    private static func copyPreferenceValue(forKey key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(
            key as CFString,
            preferencesDomain,
            kCFPreferencesAnyUser,
            kCFPreferencesCurrentHost
        )
    }

    private static func plistFallback() -> [String: Any] {
        guard
            let data = try? Data(contentsOf: loginWindowPreferencesURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return [:]
        }
        return plist
    }

    /// Maps loginwindow `ClockFontWeight` (0…1000) to an `NSFont` trait weight.
    private static func fontTraitWeight(fromSystemWeight weight: Int) -> CGFloat {
        let t = CGFloat(min(max(weight, 0), 1000)) / 1000.0
        return -0.8 + t * 1.2
    }
}

private final class LoginWindowPreferencesMonitor {
    static let shared = LoginWindowPreferencesMonitor()

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var reloadWork: DispatchWorkItem?

    func start() {
        guard source == nil else { return }
        let path = "/Library/Preferences/com.apple.loginwindow.plist"
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source.resume()
        self.source = source
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem {
            NotificationCenter.default.post(
                name: AppleLockScreenClock.preferencesDidChangeNotification,
                object: nil
            )
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
