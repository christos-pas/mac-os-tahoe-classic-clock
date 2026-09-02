import AppKit
import AVFoundation
import Darwin

/// Reads the current wallpaper from user-readable sources only.
/// No screen capture, Accessibility, or private WindowServer calls.
enum WallpaperImage {
    static let didChangeNotification = Notification.Name("LockClockWallpaperDidChange")

    private static let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    private static let aerialsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")

    static func current(for screen: NSScreen? = NSScreen.main ?? NSScreen.screens.first) -> NSImage? {
        if let image = imageFromWallpaperStore(screen: screen) {
            return image
        }
        if let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            return load(from: url)
        }
        return nil
    }

    static func startWatching() {
        WallpaperStoreMonitor.shared.start()
    }

    private static func imageFromWallpaperStore(screen: NSScreen?) -> NSImage? {
        guard
            let data = try? Data(contentsOf: storeURL),
            let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }

        if let displays = root["Displays"] as? [String: Any],
           let uuid = displayUUID(for: screen),
           let section = section(matching: uuid, in: displays),
           let image = image(fromSection: section) {
            return image
        }

        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            if let image = image(fromSection: root[key] as? [String: Any]) {
                return image
            }
        }
        return nil
    }

    private static func section(matching uuid: String, in displays: [String: Any]) -> [String: Any]? {
        let needle = uuid.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).lowercased()
        for (key, value) in displays {
            let candidate = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).lowercased()
            if candidate == needle, let section = value as? [String: Any] {
                return section
            }
        }
        return nil
    }

    private static func displayUUID(for screen: NSScreen?) -> String? {
        guard
            let screen,
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func image(fromSection section: [String: Any]?) -> NSImage? {
        guard let section else { return nil }
        for key in ["LockScreen", "Linked", "Desktop"] {
            if let block = section[key] as? [String: Any],
               let image = image(fromContentBlock: block) {
                return image
            }
        }
        return image(fromContentBlock: section)
    }

    private static func image(fromContentBlock block: [String: Any]) -> NSImage? {
        let content = (block["Content"] as? [String: Any]) ?? block
        let choices = content["Choices"] as? [[String: Any]] ?? []
        for choice in choices {
            if let image = image(fromChoice: choice) {
                return image
            }
        }
        return nil
    }

    private static func image(fromChoice choice: [String: Any]) -> NSImage? {
        if let files = choice["Files"] as? [Any] {
            for file in files {
                if let image = image(fromFileEntry: file) {
                    return image
                }
            }
        }

        let provider = choice["Provider"] as? String ?? ""
        let configuration = decodedPlist(choice["Configuration"] as? Data) ?? [:]
        if provider.contains("aerials"), let assetID = configuration["assetID"] as? String {
            return aerialStill(for: assetID)
        }
        if let urlString = configuration["url"] as? String, let image = load(from: URL(fileURLWithPath: urlString)) {
            return image
        }
        if let path = configuration["relative"] as? String, let image = NSImage(contentsOfFile: path) {
            return image
        }
        return nil
    }

    private static func image(fromFileEntry entry: Any) -> NSImage? {
        if let path = entry as? String {
            return load(from: URL(fileURLWithPath: path))
        }
        if let url = entry as? URL {
            return load(from: url)
        }
        guard let dict = entry as? [String: Any] else { return nil }
        if let url = dict["url"] as? String {
            return load(from: URL(fileURLWithPath: url))
        }
        if let relative = dict["relative"] as? String {
            return load(from: URL(fileURLWithPath: relative))
        }
        return nil
    }

    private static func aerialStill(for assetID: String) -> NSImage? {
        let thumbnail = aerialsRoot.appendingPathComponent("thumbnails/\(assetID).png")
        if let image = NSImage(contentsOf: thumbnail) {
            return image
        }
        let video = aerialsRoot.appendingPathComponent("videos/\(assetID).mov")
        if FileManager.default.isReadableFile(atPath: video.path) {
            return posterFrame(from: video)
        }
        return nil
    }

    private static func posterFrame(from videoURL: URL) -> NSImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private static func decodedPlist(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private static func load(from url: URL) -> NSImage? {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            return loadFromDirectory(url)
        }
        return NSImage(contentsOf: url)
    }

    private static func loadFromDirectory(_ url: URL) -> NSImage? {
        let extensions: Set<String> = ["heic", "jpg", "jpeg", "png", "tif", "tiff"]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let images = files
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        return images.first.flatMap { NSImage(contentsOf: $0) }
    }
}

private final class WallpaperStoreMonitor {
    static let shared = WallpaperStoreMonitor()

    private var source: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private var reloadWork: DispatchWorkItem?

    func start() {
        guard source == nil else { return }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store")
        directoryFD = open(directory.path, O_EVTONLY)
        guard directoryFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.directoryFD >= 0 else { return }
            close(self.directoryFD)
            self.directoryFD = -1
        }
        source.resume()
        self.source = source
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem {
            NotificationCenter.default.post(name: WallpaperImage.didChangeNotification, object: nil)
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
