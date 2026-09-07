import AppKit
import SwiftUI

/// Renders our lock-screen clock for comparison against a reference screenshot.
enum ClockCalibration {
    @MainActor
    static func exportOurs(to url: URL, screen: NSScreen? = NSScreen.main ?? NSScreen.screens.first) {
        guard let screen else { return }
        let appearance = Settings.shared.appearance.resolved(on: screen)
        let wallpaper = WallpaperImage.current(for: screen)
        ScreenshotExport.writeRaster(
            FullScreenClockShot(appearance: appearance, wallpaper: wallpaper, screenSize: screen.frame.size),
            size: screen.frame.size,
            scale: 2,
            to: url
        )
    }

    @MainActor
    static func run(referencePath: String, outputDirectory: URL) {
        let oursURL = outputDirectory.appendingPathComponent("ours-calibration.png")
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        exportOurs(to: oursURL)
        FileHandle.standardError.write(Data("Wrote \(oursURL.path)\n".utf8))

        let screenHeight = (NSScreen.main ?? NSScreen.screens.first)?.frame.height ?? SystemClockLayout.referenceScreenHeight
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = repoRoot.appendingPathComponent("Scripts/measure_clock.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            FileHandle.standardError.write(Data("error: missing \(script.path)\n".utf8))
            exit(1)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [
            script.path,
            referencePath,
            oursURL.path,
            String(format: "%.1f", screenHeight),
            String(format: "%.4f", SystemClockLayout.timeHeightFraction),
            String(format: "%.4f", SystemClockLayout.verticalCenterFraction),
            String(format: "%.4f", SystemClockLayout.dateOffsetRatio),
        ]
        task.currentDirectoryURL = repoRoot

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.standardError
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8),
              let jsonStart = output.firstIndex(of: "{"),
              let jsonData = output[jsonStart...].data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let suggestion = root["suggestion"] as? [String: Any],
              let timeHeightFraction = suggestion["timeHeightFraction"] as? Double,
              let verticalCenterFraction = suggestion["verticalCenterFraction"] as? Double,
              let dateOffsetRatio = suggestion["dateOffsetRatio"] as? Double else {
            FileHandle.standardError.write(Data("error: measurement failed\n".utf8))
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            exit(1)
        }

        print(output[jsonStart...])
        FileHandle.standardError.write(Data(
            String(format:
                "Apply to SystemClockLayout: timeHeightFraction=%.4f verticalCenterFraction=%.4f dateOffsetRatio=%.4f\n",
                timeHeightFraction, verticalCenterFraction, dateOffsetRatio
            ).utf8
        ))
    }
}

/// Full-screen render positioned with the same anchor as `SystemClockLayout.windowFrame`.
private struct FullScreenClockShot: View {
    var appearance: ClockAppearance
    var wallpaper: NSImage?
    var screenSize: CGSize

    @State private var clockSize: CGSize?

    var body: some View {
        ZStack {
            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
            if let clockSize {
                ClockView(appearance: appearance)
                    .position(
                        SystemClockLayout.previewCenter(
                            viewSize: clockSize,
                            appearance: appearance,
                            previewSize: screenSize,
                            screenHeight: screenSize.height
                        )
                    )
            }
            ClockView(appearance: appearance)
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
        .frame(width: screenSize.width, height: screenSize.height)
        .clipped()
    }
}

enum ClockCalibrationArguments {
    struct Parsed {
        var reference: String
        var output: URL
    }

    static func parse(from arguments: [String]) -> Parsed? {
        guard let index = arguments.firstIndex(of: "--calibrate-clock") else { return nil }
        let reference: String
        if arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("-") {
            reference = arguments[index + 1]
        } else {
            reference = NSHomeDirectory() + "/Desktop/system_clock.png"
        }
        let outputPath: String
        if arguments.indices.contains(index + 2), !arguments[index + 2].hasPrefix("-") {
            outputPath = arguments[index + 2]
        } else {
            outputPath = "docs/calibration"
        }
        return Parsed(
            reference: reference,
            output: URL(fileURLWithPath: outputPath, isDirectory: true)
        )
    }
}
