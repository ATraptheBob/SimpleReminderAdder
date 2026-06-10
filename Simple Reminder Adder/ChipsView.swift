import SwiftUI
internal import Combine

final class ChipsOverlayState: ObservableObject {
    @Published var priorityExpanded = false
}

private enum ChipKind: String {
    case priority, date, time, list, recurrence, location
}

struct ChipsView: View {
    @EnvironmentObject private var overlay: ChipsOverlayState

    var priority: Int
    var date: Date?
    var showDatePill: Bool
    var showTimePill: Bool
    var highlightDate: Bool
    var highlightTime: Bool
    var listName: String?
    var recurrenceText: String?
    var locationTitle: String?

    @State private var sliderT: Double = 0.5

    var body: some View {
        HStack(spacing: 7) {
            if priority > 0 {
                prioritySection
            }
            if let date {
                if showDatePill {
                    chip(
                        kind: .date,
                        icon: "calendar",
                        label: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                        glow: highlightDate
                    )
                }
                if showTimePill {
                    chip(
                        kind: .time,
                        icon: "clock",
                        label: date.formatted(date: .omitted, time: .shortened),
                        glow: highlightTime
                    )
                }
            }
            if let text = recurrenceText {
                chip(kind: .recurrence, icon: "repeat", label: text.capitalized, glow: false)
            }
            if let text = locationTitle {
                chip(kind: .location, icon: "location.fill", label: text, glow: false)
            }
            if let name = listName {
                chip(kind: .list, icon: "list.bullet", label: name, glow: false)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { syncSliderFromPriority() }
        .onChange(of: priority) { _, _ in syncSliderFromPriority() }
    }

    // MARK: - Priority section

    @ViewBuilder
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            chip(
                kind: .priority,
                icon: "exclamationmark.circle.fill",
                label: priorityLabel(for: displayPriority),
                glow: false
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.82)) {
                    overlay.priorityExpanded.toggle()
                    NotificationCenter.default.post(name: .chipsLayoutChanged, object: nil)
                }
            }

            if overlay.priorityExpanded {
                prioritySlider(accent: chipColor(kind: .priority))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.15, dampingFraction: 0.82), value: overlay.priorityExpanded)
    }

    private func prioritySlider(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: $sliderT, in: 0...1, onEditingChanged: { live in
                if !live {
                    let v = priorityFromSlider(sliderT)
                    NotificationCenter.default.post(
                        name: .chipPrioritySliderCommit,
                        object: nil,
                        userInfo: ["value": v]
                    )
                }
            })
            .tint(accent)
            .controlSize(.small)
        }
        .frame(width: 140)
        .padding(.horizontal, 2)
    }

    private func syncSliderFromPriority() {
        switch priority {
        case 1:  sliderT = 1.0
        case 5:  sliderT = 0.5
        case 9:  sliderT = 0.0
        default: sliderT = 0.5
        }
    }

    private func priorityFromSlider(_ t: Double) -> Int {
        if t >= 0.66 { return 1 }
        if t >= 0.33 { return 5 }
        return 9
    }

    private var displayPriority: Int {
        overlay.priorityExpanded ? priorityFromSlider(sliderT) : priority
    }

    private func priorityLabel(for p: Int) -> String {
        switch p {
        case 1:  return "High"
        case 5:  return "Medium"
        default: return "Low"
        }
    }

    // MARK: - Chip

    // Design matches the toast pills: very subtle fill, colored stroke + text.
    // Same PanelChrome tokens, same VisualEffectView backdrop.
    @ViewBuilder
    private func chip(kind: ChipKind, icon: String, label: String, glow: Bool) -> some View {
        let color = chipColor(kind: kind)
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .fixedSize()
                .lineLimit(1)
        }
        .foregroundColor(color.opacity(glow ? 1.0 : 0.85))
        .fixedSize()
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        // Subtle fill + VisualEffect blur — same approach as toast
        .background(
            ZStack {
                VisualEffectView()
                color.opacity(glow ? 0.12 : 0.06)
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(glow ? 0.45 : 0.20), lineWidth: 1)
        )
        .shadow(
            color: color.opacity(glow ? 0.18 : 0),
            radius: glow ? 4 : 0,
            y: glow ? 1 : 0
        )
        .scaleEffect(glow ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.16), value: glow)
        .modifier(SwipeChipModifier(kind: kind))
    }

    private func chipColor(kind: ChipKind) -> Color {
        switch kind {
        case .priority: return priorityColor(for: displayPriority)
        case .date, .time, .recurrence: return PanelChrome.dateTime
        case .list, .location: return PanelChrome.listAccent
        }
    }

    private func priorityColor(for p: Int) -> Color {
        switch p {
        case 1:  return PanelChrome.priorityHigh
        case 5:  return PanelChrome.priorityMed
        default: return PanelChrome.priorityLow
        }
    }
}

// MARK: - Swipe modifier (iOS only)

private struct SwipeChipModifier: ViewModifier {
    let kind: ChipKind
    func body(content: Content) -> some View {
        #if os(iOS)
        content.gesture(
            DragGesture(minimumDistance: 24).onEnded { v in
                if v.translation.width < -40 {
                    NotificationCenter.default.post(name: .chipSwipeDelete,    object: nil, userInfo: ["kind": kind.rawValue])
                } else if v.translation.width > 40 {
                    NotificationCenter.default.post(name: .chipSwipeDuplicate, object: nil, userInfo: ["kind": kind.rawValue])
                }
            }
        )
        #else
        content
        #endif
    }
}
