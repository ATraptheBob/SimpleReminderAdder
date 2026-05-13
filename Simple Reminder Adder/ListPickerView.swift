import SwiftUI
import EventKit

/// Vertical “liquid glass” list for choosing a Reminders list after typing `/`.
struct ListPickerView: View {
    let calendars: [EKCalendar]
    let selectedIndex: Int
    var onSelectIndex: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if calendars.isEmpty {
                        Text("No matching lists")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(calendars.enumerated()), id: \.offset) { index, cal in
                            row(title: cal.title, index: index)
                                .id(index)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 220)
            .onChange(of: selectedIndex) { _, new in
                proxy.scrollTo(new, anchor: .center)
            }
        }
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private func row(title: String, index: Int) -> some View {
        let isOn = index == selectedIndex
        Button {
            onSelectIndex(index)
        } label: {
            HStack {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
