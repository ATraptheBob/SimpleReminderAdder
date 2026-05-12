import SwiftUI

struct ToastView: View {
    var title: String
    var list: String
    var dateStr: String?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 20))
            
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            // 🚨 FIX: Removed the Spacer() that was stretching the window!
            
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                Text(list)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.15))
            .clipShape(Capsule())
            
            if let date = dateStr {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                    Text(date)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(VisualEffectView())
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        // Prevents the toast from accidentally exceeding your screen width if a task is massive
        .frame(maxWidth: 800)
    }
}
