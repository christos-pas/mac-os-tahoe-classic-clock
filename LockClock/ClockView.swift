import AppKit
import CoreImage
import SwiftUI

/// Screen-aligned wallpaper context for backdrop blur on the lock screen.
struct ClockBackdropContext {
    var wallpaper: NSImage
    var screenFrame: CGRect
    var windowFrame: CGRect
}

struct ClockView: View {
    var appearance: ClockAppearance
    var scale: CGFloat = 1
    /// When false, SwiftUI materials are used so Settings preview blurs the wallpaper image.
    var usesWindowBackdrop: Bool = true
    /// Lock-screen wallpaper alignment; nil until the overlay window frame is known.
    var backdropContext: ClockBackdropContext?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let type = SystemClockLayout.typography(for: appearance, scale: scale)
            let padding = SystemClockLayout.contentPadding(for: appearance, scale: scale)
            let cornerRadius = min(type.timePointSize * 0.12, 28 * scale)
            VStack(spacing: type.lineSpacing) {
                Text(Self.formattedDate(context.date))
                    .font(Font(appearance.makeFont(pointSize: type.datePointSize)))
                Text(Self.formattedTime(context.date, showSeconds: appearance.showSeconds))
                    .font(Font(appearance.makeFont(pointSize: type.timePointSize)))
            }
            .foregroundStyle(Color(appearance.color).opacity(appearance.opacity))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.top, padding.top)
            .padding(.bottom, padding.bottom)
            .padding(.leading, padding.leading)
            .padding(.trailing, padding.trailing)
            .padding(.horizontal, appearance.backdropBlur ? 24 * scale : 0)
            .padding(.vertical, appearance.backdropBlur ? 14 * scale : 0)
            .background {
                if appearance.backdropBlur {
                    backdrop(cornerRadius: cornerRadius)
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func backdrop(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if usesWindowBackdrop {
            if let backdropContext {
                ClockBackdropPanel(
                    wallpaper: backdropContext.wallpaper,
                    screenFrame: backdropContext.screenFrame,
                    windowFrame: backdropContext.windowFrame,
                    cornerRadius: cornerRadius
                )
                .clipShape(shape)
            } else {
                shape.fill(.black.opacity(0.35))
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    static func formattedTime(_ date: Date, showSeconds: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(showSeconds ? "jms" : "jm")
        return formatter.string(from: date)
    }

    static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: date)
    }
}

/// Renders a screen-aligned, Core Image–blurred wallpaper patch. `NSVisualEffectView` stays grey
/// on the lock-screen Space, so blur is done in software and drawn directly.
struct ClockBackdropPanel: NSViewRepresentable {
    var wallpaper: NSImage
    var screenFrame: CGRect
    var windowFrame: CGRect
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> ClockBackdropContainerView {
        ClockBackdropContainerView()
    }

    func updateNSView(_ view: ClockBackdropContainerView, context: Context) {
        view.configure(
            wallpaper: wallpaper,
            screenFrame: screenFrame,
            windowFrame: windowFrame,
            cornerRadius: cornerRadius
        )
    }
}

enum WallpaperBackdropBlur {
    private static let ciContext = CIContext(options: nil)
    private static var cache: [CacheKey: NSImage] = [:]

    private struct CacheKey: Hashable {
        let imageID: ObjectIdentifier
        let radiusBits: UInt
    }

    static func blurredImage(from wallpaper: NSImage, radius: CGFloat) -> NSImage? {
        let key = CacheKey(imageID: ObjectIdentifier(wallpaper), radiusBits: radius.bitPattern)
        if let cached = cache[key] { return cached }
        guard let blurred = makeBlurredImage(from: wallpaper, radius: radius) else { return nil }
        cache[key] = blurred
        return blurred
    }

    static func clearCache() {
        cache.removeAll()
    }

    private static func makeBlurredImage(from wallpaper: NSImage, radius: CGFloat) -> NSImage? {
        guard let ciImage = ciImage(from: wallpaper) else { return nil }
        let extent = ciImage.extent.integral
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: extent) else { return nil }
        guard let cgImage = ciContext.createCGImage(output, from: extent) else { return nil }
        return NSImage(cgImage: cgImage, size: wallpaper.size)
    }

    private static func ciImage(from wallpaper: NSImage) -> CIImage? {
        var rect = CGRect(origin: .zero, size: wallpaper.size)
        if let cgImage = wallpaper.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return CIImage(cgImage: cgImage)
        }
        guard let tiff = wallpaper.tiffRepresentation else { return nil }
        return CIImage(data: tiff)
    }
}

final class ClockBackdropContainerView: NSView {
    private let imageView = NSImageView()
    private let frostOverlay = NSView()

    private var wallpaper: NSImage?
    private var screenFrame: CGRect = .zero
    private var windowFrame: CGRect = .zero
    private var configuredCornerRadius: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)

        frostOverlay.wantsLayer = true
        frostOverlay.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        addSubview(frostOverlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        wallpaper: NSImage,
        screenFrame: CGRect,
        windowFrame: CGRect,
        cornerRadius: CGFloat
    ) {
        self.wallpaper = wallpaper
        self.screenFrame = screenFrame
        self.windowFrame = windowFrame
        self.configuredCornerRadius = cornerRadius
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        layer?.cornerRadius = configuredCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        frostOverlay.frame = bounds

        guard let wallpaper else { return }
        let displayImage = WallpaperBackdropBlur.blurredImage(from: wallpaper, radius: 36) ?? wallpaper
        imageView.image = displayImage
        imageView.frame = Self.aspectFillImageFrame(
            imageSize: displayImage.size,
            containerSize: screenFrame.size,
            origin: CGPoint(
                x: screenFrame.minX - windowFrame.minX,
                y: screenFrame.minY - windowFrame.minY
            )
        )
    }

    private static func aspectFillImageFrame(
        imageSize: NSSize,
        containerSize: NSSize,
        origin: CGPoint
    ) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return NSRect(origin: origin, size: containerSize)
        }
        let scale = max(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return NSRect(
            x: origin.x + (containerSize.width - width) / 2,
            y: origin.y + (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }
}
