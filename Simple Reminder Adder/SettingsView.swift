import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.simplereminderadder", category: "SettingsView")

struct SettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .system
    @AppStorage("keepPanelOpen") private var keepPanelOpen: Bool = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    // Dictation hotkey — stored as a single character string (e.g. "d")
    @AppStorage("dictationHotkey") private var dictationHotkey: String = "d"
    @State private var isRecordingHotkey = false

    // Default time definitions (hour + minute)
    @AppStorage("timeMorningHour")   private var morningHour: Int = 9
    @AppStorage("timeMorningMinute") private var morningMinute: Int = 0
    @AppStorage("timeAfternoonHour")   private var afternoonHour: Int = 14
    @AppStorage("timeAfternoonMinute") private var afternoonMinute: Int = 0
    @AppStorage("timeEveningHour")   private var eveningHour: Int = 19
    @AppStorage("timeEveningMinute") private var eveningMinute: Int = 0
    @AppStorage("timeNightHour")   private var nightHour: Int = 21
    @AppStorage("timeNightMinute") private var nightMinute: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            Text("Preferences")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.bottom, 18)

            // ── Section 1: Shortcuts ──
            sectionHeader("Shortcuts")

            HStack {
                Label("Toggle Panel", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                KeyboardShortcuts.Recorder(for: .togglePanel)
            }
            .padding(.vertical, 4)

            HStack {
                Label("Voice Dictation", systemImage: "mic")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                dictationHotkeyRecorder
            }
            .padding(.vertical, 4)

            Divider().padding(.vertical, 10)

            // ── Section 2: Time Definitions ──
            sectionHeader("Default Times")

            Text("Customize what \"morning\", \"afternoon\", etc. resolve to when parsing reminders.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            timeRow(label: "Morning",   hour: $morningHour,   minute: $morningMinute)
            timeRow(label: "Afternoon", hour: $afternoonHour, minute: $afternoonMinute)
            timeRow(label: "Evening",   hour: $eveningHour,   minute: $eveningMinute)
            timeRow(label: "Night",     hour: $nightHour,     minute: $nightMinute)

            Divider().padding(.vertical, 10)

            // ── Section 3: Behavior ──
            sectionHeader("Behavior")

            Toggle(isOn: $keepPanelOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep panel open after adding")
                        .font(.system(size: 13, weight: .medium))
                    Text("Press Enter to save without closing the panel, for rapid entry.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.vertical, 4)

            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch on login")
                        .font(.system(size: 13, weight: .medium))
                    Text("Automatically start Simple Reminder Adder when you log in.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.vertical, 4)
            .onChange(of: launchAtLogin) { oldValue, newValue in
                do {
                    if newValue {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                        }
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    logger.error("Failed to toggle launch at login: \(error.localizedDescription)")
                }
            }

            Divider().padding(.vertical, 10)

            // ── Section 4: Theme ──
            sectionHeader("Appearance")

            HStack {
                Text("Visual Theme")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(.vertical, 4)
        }
        .padding(28)
        .frame(width: 500, height: 520)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(1.2)
            .padding(.bottom, 6)
    }

    // MARK: - Dictation hotkey recorder

    private var dictationHotkeyRecorder: some View {
        Button {
            isRecordingHotkey.toggle()
        } label: {
            HStack(spacing: 4) {
                if isRecordingHotkey {
                    Text("Press a key…")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                } else {
                    Text("⌘\(dictationHotkey.uppercased())")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecordingHotkey ? Color.orange.opacity(0.12) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isRecordingHotkey ? Color.orange.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dictation Hotkey Recorder")
        .accessibilityValue(isRecordingHotkey ? "Recording" : dictationHotkey)
        .accessibilityHint("Tap to record a new hotkey for dictation")
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard isRecordingHotkey else { return event }
                if let chars = event.charactersIgnoringModifiers,
                   let ch = chars.first,
                   ch.isLetter || ch.isNumber {
                    dictationHotkey = String(ch).lowercased()
                    isRecordingHotkey = false
                    return nil
                }
                // Escape cancels recording
                if event.keyCode == 53 {
                    isRecordingHotkey = false
                    return nil
                }
                return event
            }
        }
    }

    // MARK: - Time definition row

    private func timeRow(label: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 80, alignment: .leading)
            Spacer()
            HStack(spacing: 2) {
                // Hour picker
                Picker("", selection: hour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%d", h == 0 ? 12 : (h > 12 ? h - 12 : h)))
                            .tag(h)
                    }
                }
                .frame(width: 55)

                Text(":")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))

                // Minute picker
                Picker("", selection: minute) {
                    ForEach([0, 15, 30, 45], id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .frame(width: 55)

                // AM/PM label
                Text(hour.wrappedValue < 12 ? "AM" : "PM")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }
        }
        .padding(.vertical, 3)
    }
}
