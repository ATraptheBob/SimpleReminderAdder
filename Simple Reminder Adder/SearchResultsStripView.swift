import SwiftUI

struct SearchHitRowModel: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

/// Vertical reminder hits below the quick-add field (search / "finder" menu pattern).
struct SearchResultsMenuView: View {
    let hits: [SearchHitRowModel]
    var selectedIndex: Int = 0

    var body: some View {
        Group {
            if hits.isEmpty {
                Text("Type to filter reminders")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                                row(hit, isSelected: index == selectedIndex)
                                    .id(hit.id)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 240)
                    .onChange(of: selectedIndex) { _, new in
                        if new >= 0, new < hits.count {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(hits[new].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private func row(_ hit: SearchHitRowModel, isSelected: Bool) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .searchResultActivate,
                object: nil,
                userInfo: ["id": hit.id]
            )
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? PanelChrome.searchAccent
                            : PanelChrome.searchAccent.opacity(0.75)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !hit.subtitle.isEmpty {
                        Text(hit.subtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: PanelChrome.innerCorner, style: .continuous)
                    .fill(isSelected ? PanelChrome.rowFillSelected : Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
