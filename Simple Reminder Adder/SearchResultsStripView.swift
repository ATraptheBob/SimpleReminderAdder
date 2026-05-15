import SwiftUI

struct SearchHitRowModel: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

/// Vertical reminder hits below the quick-add field (search / “finder” menu pattern).
struct SearchResultsMenuView: View {
    let hits: [SearchHitRowModel]

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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(hits) { hit in
                            row(hit)
                                .id(hit.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private func row(_ hit: SearchHitRowModel) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .searchResultActivate,
                object: nil,
                userInfo: ["id": hit.id]
            )
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelChrome.searchAccent.opacity(0.75))
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
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
                    .fill(Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
