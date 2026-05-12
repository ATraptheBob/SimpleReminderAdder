import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Preferences")
                .font(.headline)
            
            HStack {
                Text("Global Shortcut:")
                Spacer()
                // 🚨 This automatically records and saves the new shortcut!
                KeyboardShortcuts.Recorder(for: .togglePanel)
            }
        }
        .padding(30)
        .frame(width: 350, height: 120)
    }
}
