import SwiftUI

struct SearchHitRowModel: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

/// Horizontal reminder hits shown below the quick-add bar (same band as chips).
struct SearchResultsStripView: View {
    let hits: [SearchHitRowModel]

    private let accent = Color(hue: 0.55, saturation: 0.45, brightness: 0.92)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(hits) { hit in
                    Button {
                        NotificationCenter.default.post(
                            name: .searchResultActivate,
                            object: nil,
                            userInfo: ["id": hit.id]
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                            if !hit.subtitle.isEmpty {
                                Text(hit.subtitle)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(accent.opacity(0.14))
                        )
                        .overlay(
                            Capsule()
                                .stroke(accent.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: 120)
    }
}
