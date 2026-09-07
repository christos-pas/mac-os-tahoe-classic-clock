import AppKit

/// Shared size and placement for Match System Clock mode and defaults.
/// Uses the original center-anchor model (proven on built-in displays ~982 pt tall).
enum SystemClockLayout {
    struct Metrics: Equatable {
        var timePointSize: CGFloat

        func clockPlacement() -> ClockPlacement {
            ClockPlacement(horizontalFraction: 0.5, verticalFraction: SystemClockLayout.verticalCenterFraction)
        }
    }

    struct Typography {
        var timePointSize: CGFloat
        var datePointSize: CGFloat
        var lineSpacing: CGFloat
    }

    /// Calibrated against `system_clock.png` (Apple lock screen reference).
    static var timeHeightFraction: CGFloat = 0.1565
    static let minTimePointSize: CGFloat = 120
    static let maxTimePointSize: CGFloat = 220

    /// Anchor point from the top of the screen (center of the clock block).
    static var verticalCenterFraction: CGFloat = 0.247
    /// Nudges the window up so the time line sits on the anchor (date sits above).
    static var dateOffsetRatio: CGFloat = 0.22

    private static let dateSizeRatio: CGFloat = 0.20
    private static let lineSpacingRatio: CGFloat = 0.02

    static let referenceScreenHeight: CGFloat = 982

    static var defaultAppearancePlacement: ClockPlacement {
        ClockPlacement(horizontalFraction: 0.5, verticalFraction: verticalCenterFraction)
    }

    static var defaultTimePointSize: CGFloat {
        metrics(forHeight: referenceScreenHeight).timePointSize
    }

    static func metrics(for screen: NSScreen) -> Metrics {
        metrics(forHeight: screen.frame.height)
    }

    static func metrics(forHeight height: CGFloat) -> Metrics {
        let size = min(maxTimePointSize, max(minTimePointSize, height * timeHeightFraction))
        return Metrics(timePointSize: size)
    }

    static func typography(for appearance: ClockAppearance, scale: CGFloat = 1) -> Typography {
        let time = appearance.size * scale
        if appearance.matchSystemClock {
            return Typography(
                timePointSize: time,
                datePointSize: time * dateSizeRatio,
                lineSpacing: max(2, time * lineSpacingRatio)
            )
        }
        return Typography(
            timePointSize: time,
            datePointSize: time / 5,
            lineSpacing: max(0.8, time * 0.02)
        )
    }

    static func contentPadding(for appearance: ClockAppearance, scale: CGFloat = 1) -> (
        top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat
    ) {
        if appearance.matchSystemClock {
            return (0, 0, 0, 0)
        }
        let padH = 24 * scale
        let padV = 8 * scale
        return (padV, padH, padV, padH)
    }

    static func windowFrame(
        viewSize: NSSize,
        appearance: ClockAppearance,
        on screen: NSScreen
    ) -> NSRect {
        let width = max(viewSize.width, 80)
        let height = max(viewSize.height, 40)
        let x = screen.frame.minX + screen.frame.width * appearance.placement.horizontalFraction - width / 2
        let yFromTop = screen.frame.height * appearance.placement.verticalFraction
        let dateOffset = appearance.size * dateOffsetRatio
        let y = screen.frame.maxY - yFromTop - height / 2 + dateOffset
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func previewCenter(
        viewSize: CGSize,
        appearance: ClockAppearance,
        previewSize: CGSize,
        screenHeight: CGFloat
    ) -> CGPoint {
        let scale = previewSize.height / max(screenHeight, 1)
        let yFromTop = previewSize.height * appearance.placement.verticalFraction
        let dateOffset = appearance.size * dateOffsetRatio * scale
        return CGPoint(
            x: previewSize.width * appearance.placement.horizontalFraction,
            y: yFromTop - dateOffset
        )
    }

    static func applyCalibration(_ suggestion: ClockCalibrationSuggestion) {
        timeHeightFraction = suggestion.timeHeightFraction
        verticalCenterFraction = suggestion.verticalCenterFraction
        dateOffsetRatio = suggestion.dateOffsetRatio
    }
}

struct ClockCalibrationSuggestion: Equatable {
    var timeHeightFraction: CGFloat
    var verticalCenterFraction: CGFloat
    var dateOffsetRatio: CGFloat
}
