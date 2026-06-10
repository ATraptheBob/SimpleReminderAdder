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

    @State private var completedRowIDs: Set<String> = []

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
        .onReceive(NotificationCenter.default.publisher(for: .searchCompleteSelected)) { _ in
            guard selectedIndex >= 0, selectedIndex < hits.count else { return }
            let hit = hits[selectedIndex]
            triggerCompletion(hitID: hit.id)
        }
    }

    private func triggerCompletion(hitID: String) {
        guard !completedRowIDs.contains(hitID) else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            _ = completedRowIDs.insert(hitID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .searchResultComplete,
                object: nil,
                userInfo: ["id": hitID]
            )
            completedRowIDs.remove(hitID)
        }
    }

    @ViewBuilder
    private func row(_ hit: SearchHitRowModel, isSelected: Bool) -> some View {
        let isCompleted = completedRowIDs.contains(hit.id)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                triggerCompletion(hitID: hit.id)
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : (isSelected ? "checkmark.circle.fill" : "checkmark.circle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        isCompleted
                            ? Color.green
                            : (isSelected ? PanelChrome.searchAccent : PanelChrome.searchAccent.opacity(0.75))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                NotificationCenter.default.post(
                    name: .searchResultActivate,
                    object: nil,
                    userInfo: ["id": hit.id]
                )
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .strikethrough(isCompleted, color: .primary.opacity(0.4))
                    if !hit.subtitle.isEmpty {
                        Text(hit.subtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: PanelChrome.innerCorner, style: .continuous)
                .fill(isSelected ? PanelChrome.rowFillSelected : Color.primary.opacity(0.04))
        )
        .opacity(isCompleted ? 0.35 : 1.0)
        .animation(.easeOut(duration: 0.25), value: isCompleted)
    }
}
