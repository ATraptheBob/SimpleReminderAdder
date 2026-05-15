import SwiftUI
internal import Combine

final class ChipsOverlayState: ObservableObject {
    @Published var priorityExpanded = false
}

private enum ChipSwipeKind: String {
    case priority, date, time, list
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

    @State private var sliderT: Double = 0.5

    var body: some View {
        HStack(spacing: 8) {
            if priority > 0 {
                prioritySection
            }
            if let date {
                if showDatePill {
                    chip(kind: .date, icon: "calendar", label: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), glow: highlightDate)
                }
                if showTimePill {
                    chip(kind: .time, icon: "clock", label: date.formatted(date: .omitted, time: .shortened), glow: highlightTime)
                }
            }
            if let name = listName {
                chip(kind: .list, icon: "list.bullet", label: name, glow: false)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { syncSliderFromPriority() }
        .onChange(of: priority) { _, _ in syncSliderFromPriority() }
    }

    @ViewBuilder
    private var prioritySection: some View {
        let c = priorityColor(for: displayPriority)
        VStack(alignment: .leading, spacing: 6) {
            chip(kind: .priority, icon: "exclamationmark.circle.fill", label: priorityLabel(for: displayPriority), glow: false)
                .onTapGesture {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        overlay.priorityExpanded.toggle()
                        NotificationCenter.default.post(name: .chipsLayoutChanged, object: nil)
                    }
                }
            if overlay.priorityExpanded {
                prioritySlider(accent: c)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: overlay.priorityExpanded)
    }

    private func prioritySlider(accent: Color) -> some View {
        let trackLow = Color.primary.opacity(0.12)
        return VStack(alignment: .leading, spacing: 4) {
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
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [trackLow, accent.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 5)
                    .padding(.horizontal, 2)
                    .allowsHitTesting(false)
            )
        }
        .frame(width: 148)
    }

    private func syncSliderFromPriority() {
        switch priority {
        case 1: sliderT = 1
        case 5: sliderT = 0.5
        case 9: sliderT = 0
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
        case 1: return "High"
        case 5: return "Medium"
        default: return "Low"
        }
    }

    @ViewBuilder
    private func chip(kind: ChipSwipeKind, icon: String, label: String, glow: Bool) -> some View {
        let color = chipColor(kind: kind)
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
                Capsule().fill(color.opacity(glow ? PanelChrome.chipFillGlow : PanelChrome.chipFillRest))
                Capsule().fill(Material.ultraThinMaterial)
                    .opacity(PanelChrome.chipMaterialOpacity)
            }
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(glow ? PanelChrome.chipStrokeGlow : PanelChrome.chipStrokeRest), lineWidth: glow ? 1.25 : 1)
        )
        .shadow(color: color.opacity(glow ? PanelChrome.chipShadowGlow : 0), radius: glow ? PanelChrome.chipShadowRadius : 0, y: 0)
        .scaleEffect(glow ? 1.01 : 1)
        .animation(.easeOut(duration: 0.18), value: glow)
        .modifier(SwipeChipModifier(kind: kind))
    }

    private func chipColor(kind: ChipSwipeKind) -> Color {
        switch kind {
        case .priority: return priorityColor(for: displayPriority)
        case .date, .time: return PanelChrome.dateTime
        case .list: return PanelChrome.listAccent
        }
    }

    private func priorityColor(for p: Int) -> Color {
        switch p {
        case 1: return PanelChrome.priorityHigh
        case 5: return PanelChrome.priorityMed
        default: return PanelChrome.priorityLow
        }
    }
}

private struct SwipeChipModifier: ViewModifier {
    let kind: ChipSwipeKind

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { v in
                        if v.translation.width < -40 {
                            NotificationCenter.default.post(name: .chipSwipeDelete, object: nil, userInfo: ["kind": kind.rawValue])
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
