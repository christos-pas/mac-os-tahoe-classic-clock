import SwiftUI

struct ClockView: View {
    var appearance: ClockAppearance
    var scale: CGFloat = 1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let scaledSize = appearance.size * scale
            VStack(spacing: max(0.8, scaledSize * 0.02)) {
                Text(Self.formattedDate(context.date))
                    .font(Font(appearance.makeFont(pointSize: scaledSize / 5)))
                Text(Self.formattedTime(context.date, showSeconds: appearance.showSeconds))
                    .font(Font(appearance.makeFont(pointSize: scaledSize)))
            }
            .foregroundStyle(Color(appearance.color).opacity(appearance.opacity))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 24 * scale)
            .padding(.vertical, 8 * scale)
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
