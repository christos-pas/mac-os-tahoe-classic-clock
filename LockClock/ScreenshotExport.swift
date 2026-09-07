import AppKit
import SwiftUI

enum ScreenshotExport {
    private static let exportScale: CGFloat = 2

    static func outputDirectory(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "--export-screenshots") else { return nil }
        let path: String
        if arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("-") {
            path = arguments[index + 1]
        } else {
            path = "docs/screenshots"
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @MainActor
    static func write(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = SettingsModel()
        let wallpaper = WallpaperImage.current()

        write(
            SettingsWindowShot(model: model),
            size: CGSize(width: 820, height: 588),
            to: directory.appendingPathComponent("settings.png")
        )
        write(
            LockScreenPreview(
                appearance: model.liveAppearance,
                enabled: true,
                wallpaper: wallpaper
            ),
            size: CGSize(width: 1280, height: 800),
            to: directory.appendingPathComponent("lock-screen.png")
        )
        write(
            MenuBarShot(),
            size: CGSize(width: 1280, height: 220),
            to: directory.appendingPathComponent("menu-bar.png")
        )
        FileHandle.standardError.write(Data("Wrote screenshots to \(directory.path)\n".utf8))
    }

    @MainActor
    private static func write<V: View>(_ view: V, size: CGSize, to url: URL) {
        writeRaster(view, size: size, scale: exportScale, to: url)
    }

    @MainActor
    static func writeRaster(_ view: NSView, size: CGSize, scale: CGFloat, to url: URL) {
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            FileHandle.standardError.write(Data("error: could not create bitmap for \(url.lastPathComponent)\n".utf8))
            return
        }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("error: could not encode \(url.lastPathComponent)\n".utf8))
            return
        }
        do {
            try data.write(to: url)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        }
    }

    @MainActor
    static func writeRaster<V: View>(_ view: V, size: CGSize, scale: CGFloat, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.contentsScale = scale
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            FileHandle.standardError.write(Data("error: could not create bitmap for \(url.lastPathComponent)\n".utf8))
            return
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("error: could not encode \(url.lastPathComponent)\n".utf8))
            return
        }
        do {
            try data.write(to: url)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        }
    }
}

private struct SettingsWindowShot: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                trafficLight(.red)
                trafficLight(.yellow)
                trafficLight(.green)
                Spacer()
                Text("Lock Clock Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 52)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.bar)
            SettingsView(model: model)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .frame(width: 820, height: 588)
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.85))
            .frame(width: 12, height: 12)
    }
}

private struct MenuBarShot: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            menuBar
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                menu
                Color.clear.frame(width: 96)
            }
        }
        .frame(width: 1280, height: 220, alignment: .top)
        .background(Color(white: 0.78))
    }

    private var menuBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "apple.logo")
                .font(.system(size: 13, weight: .medium))
            Text("Finder")
                .fontWeight(.bold)
            Text("File")
            Text("Edit")
            Text("View")
            Text("Go")
            Text("Window")
            Text("Help")
            Spacer(minLength: 12)
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            clockItem
            Text(Self.menuBarTime)
                .monospacedDigit()
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Color(white: 0.93))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    private var clockItem: some View {
        Image(systemName: "clock")
            .font(.system(size: 13, weight: .medium))
            .frame(width: 22, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.14))
            )
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("Settings…")
            Divider()
            menuRow("Quit Lock Clock")
        }
        .padding(.vertical, 5)
        .frame(width: 228, alignment: .leading)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    private func menuRow(_ title: String, checked: Bool = false) -> some View {
        HStack {
            Text(checked ? "✓" : " ")
                .frame(width: 16)
            Text(title)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private static var menuBarTime: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEjm")
        return formatter.string(from: Date())
    }
}
