import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    @State private var currentCombo: HotKeyCombo
    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?

    @State private var selectedDatePreset: DateFormatPreset
    @State private var selectedTimePreset: TimeFormatPreset
    @State private var customDateFormat: String
    @State private var customTimeFormat: String
    @State private var prefixDraft: String

    init(appState: AppState) {
        self.appState = appState
        _currentCombo = State(initialValue: HotKeyCombo.parse(appState.preferences.shortcutKey) ?? .default)
        _selectedDatePreset = State(initialValue: DateFormatPreset.preset(for: appState.preferences.fileDateFormat))
        _selectedTimePreset = State(initialValue: TimeFormatPreset.preset(for: appState.preferences.timeFormat))
        _customDateFormat = State(initialValue: appState.preferences.fileDateFormat)
        _customTimeFormat = State(initialValue: appState.preferences.timeFormat)
        _prefixDraft = State(initialValue: appState.preferences.fileNamePrefix)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                shortcutCard
                storageCard
                namingCard
                captureCard
                resetCard

                if let message = appState.settingsMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }
            }
            .padding(20)
        }
        .frame(width: 640, height: 520)
        .onDisappear {
            stopShortcutRecording()
        }
    }

    private var shortcutCard: some View {
        SettingsCard(title: "Shortcut", subtitle: "Global capture hotkey") {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow(label: "Current") {
                    Text(currentCombo.displayString)
                        .font(.system(.body, design: .monospaced))
                }

                HStack(spacing: 8) {
                    Button(isRecordingShortcut ? "Press keys..." : "Record Shortcut") {
                        toggleShortcutRecording()
                    }

                    if isRecordingShortcut {
                        Button("Cancel") {
                            stopShortcutRecording()
                        }
                    }
                }

                Text("Use at least one modifier (⌃⌥⇧⌘).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageCard: some View {
        SettingsCard(title: "Storage", subtitle: "Where daily markdown files are written") {
            VStack(alignment: .leading, spacing: 10) {
                Text(appState.currentStoragePath)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                    )

                Button("Choose Folder") {
                    appState.chooseStorageFolder()
                }
            }
        }
    }

    private var namingCard: some View {
        SettingsCard(title: "File & Time", subtitle: "Control naming and timestamp formatting") {
            VStack(alignment: .leading, spacing: 12) {
                SettingRow(label: "File prefix") {
                    TextField("Optional", text: $prefixDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            appState.updateFileNamePrefix(prefixDraft)
                            prefixDraft = appState.preferences.fileNamePrefix
                        }
                }

                SettingRow(label: "Date format") {
                    Picker("", selection: $selectedDatePreset) {
                        ForEach(DateFormatPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedDatePreset) { preset in
                        guard let format = preset.formatString else {
                            return
                        }
                        customDateFormat = format
                        appState.updateFileDateFormat(format)
                    }
                }

                if selectedDatePreset == .custom {
                    HStack(spacing: 8) {
                        TextField("Custom date format", text: $customDateFormat)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                appState.updateFileDateFormat(customDateFormat)
                            }
                        Button("Apply") {
                            appState.updateFileDateFormat(customDateFormat)
                        }
                    }
                }

                SettingRow(label: "Time format") {
                    Picker("", selection: $selectedTimePreset) {
                        ForEach(TimeFormatPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedTimePreset) { preset in
                        guard let format = preset.formatString else {
                            return
                        }
                        customTimeFormat = format
                        appState.updateTimeFormat(format)
                    }
                }

                if selectedTimePreset == .custom {
                    HStack(spacing: 8) {
                        TextField("Custom time format", text: $customTimeFormat)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                appState.updateTimeFormat(customTimeFormat)
                            }
                        Button("Apply") {
                            appState.updateTimeFormat(customTimeFormat)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Example file: \(appState.settingsPreviewFileName)")
                    Text("Example line: \(appState.settingsPreviewLine)")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
        }
    }

    private var captureCard: some View {
        SettingsCard(title: "Capture", subtitle: "Behavior after saving") {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow(label: "After save") {
                    Picker("", selection: Binding(
                        get: { appState.preferences.afterSaveMode },
                        set: { appState.updateAfterSaveMode($0) }
                    )) {
                        ForEach(AfterSaveMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { appState.preferences.launchAtLogin },
                    set: { appState.updateLaunchAtLogin($0) }
                ))
            }
        }
    }

    private var resetCard: some View {
        SettingsCard(title: "Reset", subtitle: "Restore all settings to defaults") {
            Button("Reset to defaults", role: .destructive) {
                resetToDefaults()
            }
        }
    }

    private func toggleShortcutRecording() {
        if isRecordingShortcut {
            stopShortcutRecording()
            return
        }

        isRecordingShortcut = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingShortcut else {
                return event
            }

            guard let combo = HotKeyCombo(event: event) else {
                NSSound.beep()
                return nil
            }

            currentCombo = combo
            appState.updateShortcut(combo)
            stopShortcutRecording()
            return nil
        }
    }

    private func stopShortcutRecording() {
        isRecordingShortcut = false
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }

    private func resetToDefaults() {
        appState.resetPreferencesToDefaults()
        currentCombo = HotKeyCombo.parse(appState.preferences.shortcutKey) ?? .default
        selectedDatePreset = DateFormatPreset.preset(for: appState.preferences.fileDateFormat)
        selectedTimePreset = TimeFormatPreset.preset(for: appState.preferences.timeFormat)
        customDateFormat = appState.preferences.fileDateFormat
        customTimeFormat = appState.preferences.timeFormat
        prefixDraft = appState.preferences.fileNamePrefix
        stopShortcutRecording()
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
