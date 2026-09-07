import AppKit
import SwiftUI

/// Lock-screen miniature with an oversized clock for small icon sizes.
struct AppIconView: View {
    var wallpaper: NSImage?

    private let canvas: CGFloat = 1024

    var body: some View {
        ZStack {
            wallpaperBackground
            legibilityGradient
            clockOverlay
        }
        .frame(width: canvas, height: canvas)
        .clipped()
    }

    @ViewBuilder
    private var wallpaperBackground: some View {
        if let wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: canvas, height: canvas)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.48, green: 0.60, blue: 0.74),
                    Color(red: 0.30, green: 0.46, blue: 0.34),
                    Color(red: 0.14, green: 0.30, blue: 0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var legibilityGradient: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.42),
                Color.black.opacity(0.08),
                Color.black.opacity(0.22)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var clockOverlay: some View {
        VStack(spacing: canvas * 0.01) {
            Text("Wed, Sep 2")
                .font(.system(size: canvas * 0.054, weight: .regular))
                .minimumScaleFactor(0.5)
            Text("9:41")
                .font(.system(size: canvas * 0.30, weight: .regular))
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(.white.opacity(0.88))
        .shadow(color: .black.opacity(0.40), radius: canvas * 0.012, y: canvas * 0.006)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas * 0.14)
    }
}

enum AppIconExport {
  private static let iconSetPath = "LockClock/Assets.xcassets/AppIcon.appiconset"

  static func appIconSetURL(from arguments: [String]) -> URL? {
      guard arguments.contains("--export-icon") else { return nil }
      if let index = arguments.firstIndex(of: "--export-icon"),
         arguments.indices.contains(index + 1),
         !arguments[index + 1].hasPrefix("-") {
          return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
      }
      return URL(fileURLWithPath: iconSetPath, isDirectory: true)
  }

  @MainActor
  static func write(to appIconSet: URL) {
      try? FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
      let master = appIconSet.appendingPathComponent("icon_1024.png")
      ScreenshotExport.writeRaster(
          AppIconView(wallpaper: WallpaperImage.current()),
          size: CGSize(width: 1024, height: 1024),
          scale: 1,
          to: master
      )

      let sizes = [16, 32, 64, 128, 256, 512]
      for size in sizes {
          let destination = appIconSet.appendingPathComponent("icon_\(size).png")
          resize(master, to: size, destination: destination)
      }
      FileHandle.standardError.write(Data("Wrote app icon to \(appIconSet.path)\n".utf8))
  }

  private static func resize(_ source: URL, to pixelSize: Int, destination: URL) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
      process.arguments = [
          "-z", String(pixelSize), String(pixelSize),
          source.path,
          "--out", destination.path
      ]
      try? process.run()
      process.waitUntilExit()
  }
}
