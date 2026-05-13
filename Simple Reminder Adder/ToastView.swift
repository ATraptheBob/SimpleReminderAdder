import SwiftUI

struct ToastView: View {
    var title: String
    var list: String
    var dateStr: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hue: 0.38, saturation: 0.45, brightness: 0.78))
                .font(.system(size: 14, weight: .medium))

            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            pill(
                icon: "list.bullet",
                label: list,
                color: Color(hue: 0.75, saturation: 0.35, brightness: 0.80)
            )

            if let dateStr {
                pill(
                    icon: "clock",
                    label: dateStr,
                    color: Color(hue: 0.08, saturation: 0.55, brightness: 0.85)
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
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
            Capsule().stroke(color.opacity(0.20), lineWidth: 1)
        )
    }
}
