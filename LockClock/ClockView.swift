import AppKit
import SwiftUI

struct ClockView: View {
    var appearance: ClockAppearance
    var scale: CGFloat = 1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let type = SystemClockLayout.typography(for: appearance, scale: scale)
            let padding = SystemClockLayout.contentPadding(for: appearance, scale: scale)
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
        }
        .fixedSize()
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
