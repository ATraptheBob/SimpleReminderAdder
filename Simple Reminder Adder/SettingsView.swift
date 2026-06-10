import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .system

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

            HStack {
                Text("Visual Theme:")
                Spacer()
                Picker("", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
        .padding(30)
        .frame(width: 420, height: 160)
    }
}
