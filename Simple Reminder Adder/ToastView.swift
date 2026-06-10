import SwiftUI

struct ToastView: View {
    var title: String
    var list: String
    var dateStr: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hue: 0.36, saturation: 0.32, brightness: 0.72))
                .font(.system(size: 14, weight: .medium))

            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            pill(
                icon: "list.bullet",
                label: list,
                color: PanelChrome.listAccent
            )

            if let dateStr {
                pill(
                    icon: "clock",
                    label: dateStr,
                    color: PanelChrome.dateTime
                )
            }
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(VisualEffectView())
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(PanelChrome.strokeSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundColor(color.opacity(0.85))
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.primary.opacity(0.04))
        )
        .overlay(
            Capsule().stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}
