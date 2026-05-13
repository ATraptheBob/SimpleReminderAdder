import SwiftUI

struct ChipsView: View {
    var priority: Int
    var date: Date?
    var listName: String?

    var body: some View {
        HStack(spacing: 8) {
            if priority > 0 {
                chip(
                    icon: "exclamationmark.circle.fill",
                    label: priority == 1 ? "High" : (priority == 5 ? "Medium" : "Low"),
                    color: priorityColor()
                )
            }
            if let date {
                chip(
                    icon: "clock",
                    label: date.formatted(.dateTime.weekday().day().hour().minute()),
                    color: Color(hue: 0.08, saturation: 0.6, brightness: 0.95)
                )
            }
            if let name = listName {
                chip(
                    icon: "list.bullet",
                    label: name,
                    color: Color(hue: 0.75, saturation: 0.4, brightness: 0.90)
                )
            }
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func chip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .fixedSize()
                .lineLimit(1)
        }
        .foregroundColor(color)
        .fixedSize()
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(
            ZStack {
                Capsule().fill(color.opacity(0.18))
                Capsule().fill(Material.ultraThinMaterial)
                    .opacity(0.5)
            }
        )
        .overlay(
            Capsule().stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    private func priorityColor() -> Color {
        switch priority {
        case 1:  return Color(hue: 0.0,  saturation: 0.6, brightness: 0.95)
        case 5:  return Color(hue: 0.11, saturation: 0.6, brightness: 0.95)
        default: return Color(hue: 0.60, saturation: 0.5, brightness: 0.90)
        }
    }
}
