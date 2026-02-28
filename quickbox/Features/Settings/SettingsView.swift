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
    @State private var previewFileName: String
    @FocusState private var isPrefixFieldFocused: Bool

    init(appState: AppState) {
        self.appState = appState
        let initialPreferences = appState.preferences
        var previewPreferences = initialPreferences
        previewPreferences.fileNamePrefix = FormatSettings.sanitizePrefix(initialPreferences.fileNamePrefix)
        _currentCombo = State(initialValue: HotKeyCombo.parse(appState.preferences.shortcutKey) ?? .default)
        _selectedDatePreset = State(initialValue: DateFormatPreset.preset(for: initialPreferences.fileDateFormat))
        _selectedTimePreset = State(initialValue: TimeFormatPreset.preset(for: initialPreferences.timeFormat))
        _customDateFormat = State(initialValue: initialPreferences.fileDateFormat)
        _customTimeFormat = State(initialValue: initialPreferences.timeFormat)
        _prefixDraft = State(initialValue: initialPreferences.fileNamePrefix)
        _previewFileName = State(initialValue: FormatSettings.fileName(for: Date(), preferences: previewPreferences))
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
                updatesCard
                privacyCard
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
        .onReceive(appState.$preferences) { _ in
            refreshPreviewFileName()
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
                        .focused($isPrefixFieldFocused)
                        .onChange(of: prefixDraft) {
                            refreshPreviewFileName()
                        }
                        .onSubmit {
                            persistPrefixDraftIfNeeded()
                        }
                }

                SettingRow(label: "Date format") {
                    Picker("", selection: $selectedDatePreset) {
                        ForEach(DateFormatPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedDatePreset) { _, preset in
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
                    .onChange(of: selectedTimePreset) { _, preset in
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
                    Text("Example file: \(previewFileName)")
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
        .onChange(of: isPrefixFieldFocused) { _, focused in
            if !focused {
                persistPrefixDraftIfNeeded()
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

    private var updatesCard: some View {
        SettingsCard(title: "Updates", subtitle: "Public beta update channel") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { appState.preferences.autoUpdateEnabled },
                    set: { appState.updateAutoUpdate($0) }
                ))

                Toggle("Use beta update channel", isOn: Binding(
                    get: { appState.preferences.betaChannelEnabled },
                    set: { appState.updateBetaChannelEnabled($0) }
                ))

                Button("Check for Updates") {
                    appState.checkForUpdates()
                }
            }
        }
    }

    private var privacyCard: some View {
        SettingsCard(title: "Privacy & Diagnostics", subtitle: "Crash-only diagnostics, disabled by default") {
            Toggle("Share anonymous crash reports", isOn: Binding(
                get: { appState.preferences.crashReportingEnabled },
                set: { appState.updateCrashReportingConsent($0) }
            ))
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
        refreshPreviewFileName()
        stopShortcutRecording()
    }

    private func persistPrefixDraftIfNeeded() {
        let sanitizedDraft = FormatSettings.sanitizePrefix(prefixDraft)
        guard sanitizedDraft != appState.preferences.fileNamePrefix else {
            prefixDraft = sanitizedDraft
            return
        }

        appState.updateFileNamePrefix(sanitizedDraft)
        prefixDraft = appState.preferences.fileNamePrefix
        refreshPreviewFileName()
    }

    private func refreshPreviewFileName() {
        var previewPreferences = appState.preferences
        previewPreferences.fileNamePrefix = FormatSettings.sanitizePrefix(prefixDraft)
        previewFileName = FormatSettings.fileName(for: Date(), preferences: previewPreferences)
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
