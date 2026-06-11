import SwiftUI

struct SearchHitRowModel: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let isCompleted: Bool
    let dueDate: Date?
}


/// Vertical reminder hits below the quick-add field (search / "finder" menu pattern).
struct SearchResultsMenuView: View {
    let hits: [SearchHitRowModel]
    var selectedIndex: Int = 0

    @State private var completedRowIDs: Set<String> = []
    @State private var deletedRowIDs: Set<String> = []

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
                                if !deletedRowIDs.contains(hit.id) {
                                    row(hit, isSelected: index == selectedIndex)
                                        .id(hit.id)
                                        .transition(.asymmetric(
                                            insertion: .identity,
                                            removal: .opacity.combined(with: .scale(scale: 0.92))
                                        ))
                                }
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
        .onReceive(NotificationCenter.default.publisher(for: .searchDeleteSelected)) { _ in
            guard selectedIndex >= 0, selectedIndex < hits.count else { return }
            let hit = hits[selectedIndex]
            triggerDeletion(hitID: hit.id)
        }
    }

    // MARK: - Status indicator color

    private func statusIndicatorColor(for hit: SearchHitRowModel) -> Color? {
        if hit.isCompleted || completedRowIDs.contains(hit.id) {
            return Color(hue: 0.36, saturation: 0.55, brightness: 0.72) // green
        }
        if let due = hit.dueDate, due < Date() {
            return Color(hue: 0.06, saturation: 0.60, brightness: 0.85) // warm orange-red for overdue
        }
        return nil
    }

    // MARK: - Completion

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

    // MARK: - Deletion

    private func triggerDeletion(hitID: String) {
        guard !deletedRowIDs.contains(hitID) else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            _ = deletedRowIDs.insert(hitID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: .searchResultDelete,
                object: nil,
                userInfo: ["id": hitID]
            )
            deletedRowIDs.remove(hitID)
        }
    }

    @ViewBuilder
    private func row(_ hit: SearchHitRowModel, isSelected: Bool) -> some View {
        let isCompleted = completedRowIDs.contains(hit.id) || hit.isCompleted
        let indicatorColor = statusIndicatorColor(for: hit)

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Status indicator ring + checkmark button
            Button {
                triggerCompletion(hitID: hit.id)
            } label: {
                ZStack {
                    // Outer status ring
                    if let color = indicatorColor {
                        Circle()
                            .stroke(color.opacity(0.55), lineWidth: 2)
                            .frame(width: 18, height: 18)
                    }

                    Image(systemName: isCompleted ? "checkmark.circle.fill" : (isSelected ? "checkmark.circle.fill" : "checkmark.circle"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isCompleted
                                ? Color(hue: 0.36, saturation: 0.55, brightness: 0.72)
                                : (isSelected ? PanelChrome.searchAccent : PanelChrome.searchAccent.opacity(0.75))
                        )
                }
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? "Completed" : "Mark as complete")
            .help(isCompleted ? "Completed" : "Mark as complete")

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
                        HStack(spacing: 4) {
                            // Overdue badge
                            if let due = hit.dueDate, due < Date(), !hit.isCompleted {
                                Text("overdue")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(hue: 0.06, saturation: 0.60, brightness: 0.85))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(Color(hue: 0.06, saturation: 0.60, brightness: 0.85).opacity(0.12))
                                    )
                            }
                            Text(hit.subtitle)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)

                // Keyboard hint for selected row
                if isSelected {
                    HStack(spacing: 3) {
                        Text("⇧␣")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("⇧⌫")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.trailing, 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select reminder: \(hit.title)")
            .accessibilityHint("Double tap to activate this reminder")
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
