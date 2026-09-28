import AppKit
import Combine
import QuickboxCore
import SwiftUI

struct SettingsView: View {
    private enum Style {
        static let windowBackground = Color(nsColor: .windowBackgroundColor)
        static let fill = Color(nsColor: .labelColor).opacity(0.05)
        static let controlRadius: CGFloat = 6
    }

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
    @State private var isCloudConnected = false
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
                    .foregroundStyle(.primary)

                shortcutCard
                storageCard
                if let cloudSync = appState.cloudSync {
                    CloudSyncCard(appState: appState, cloudSync: cloudSync)
                }
                namingCard
                    .disabled(isCloudConnected)
                captureCard
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
        .background(Style.windowBackground)
        .frame(width: 640, height: 520)
        .onDisappear {
            stopShortcutRecording()
        }
        .onReceive(appState.$preferences) { _ in
            refreshPreviewFileName()
        }
        .onReceive(cloudConnectionPublisher) { connected in
            isCloudConnected = connected
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
                    Button(isRecordingShortcut ? "Press keys…" : "Record shortcut") {
                        toggleShortcutRecording()
                    }
                    .controlSize(.small)

                    if isRecordingShortcut {
                        Button("Cancel") {
                            stopShortcutRecording()
                        }
                        .controlSize(.small)
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
                        RoundedRectangle(cornerRadius: Style.controlRadius, style: .continuous)
                            .fill(Style.fill)
                    )

                Button("Choose folder") {
                    appState.chooseStorageFolder()
                }
                .controlSize(.small)
            }
        }
    }

    private var cloudConnectionPublisher: AnyPublisher<Bool, Never> {
        appState.cloudSync?.$isConnected.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()
    }

    private var namingCard: some View {
        SettingsCard(
            title: "File and time",
            subtitle: isCloudConnected ? "Fixed while quickbox Cloud is connected" : "Control naming and timestamp formatting"
        ) {
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
                        .controlSize(.small)
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
                        .controlSize(.small)
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
                    RoundedRectangle(cornerRadius: Style.controlRadius, style: .continuous)
                        .fill(Style.fill)
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
            .controlSize(.small)
        }
    }

    private var privacyCard: some View {
        SettingsCard(title: "Privacy and diagnostics", subtitle: "Crash-only diagnostics, disabled by default") {
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

private struct CloudSyncCard: View {
    @ObservedObject var appState: AppState
    @ObservedObject var cloudSync: CloudSyncController
    @State private var isConnecting = false
    @State private var isConfirmingDeletion = false
    @State private var isWorking = false

    var body: some View {
        SettingsCard(title: "quickbox Cloud", subtitle: "Optional. Sync with your devices and AI agents") {
            VStack(alignment: .leading, spacing: 10) {
                if cloudSync.isConnected {
                    connectedContent
                } else {
                    disconnectedContent
                }

                if let message = cloudSync.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: cloudSync.isConnected) {
            await cloudSync.refreshAccount()
        }
        .confirmationDialog("Delete your quickbox Cloud account?", isPresented: $isConfirmingDeletion) {
            Button("Delete account and cloud data", role: .destructive) {
                run { await cloudSync.deleteAccount() }
            }
        } message: {
            Text("This permanently deletes the cloud copy of your tasks and notes and disconnects every app and agent. The files in your local folder are not touched.")
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
        SettingRow(label: "Account") {
            Text(cloudSync.account?.email ?? "—")
        }
        SettingRow(label: "Status") {
            Text(statusText)
        }
        SettingRow(label: "Agents") {
            Text(CloudConfiguration.baseURL.appendingPathComponent("mcp").absoluteString)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }

        if let apps = cloudSync.account?.apps, !apps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connected apps")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(apps) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.isThisDevice ? "\(app.name) (this Mac)" : app.name)
                            Text("Connected \(app.connectedDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !app.isThisDevice {
                            Button("Disconnect") {
                                run { await cloudSync.disconnectApp(app) }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }

        HStack(spacing: 8) {
            Button("Sync now") {
                Task { await cloudSync.syncNow() }
            }
            .disabled(cloudSync.isSyncing)
            Button("Disconnect this Mac") {
                run { await appState.disconnectCloudSync() }
            }
            Spacer()
            Button("Delete account…", role: .destructive) {
                isConfirmingDeletion = true
            }
        }
        .controlSize(.small)
        .disabled(isWorking)
    }

    @ViewBuilder
    private var disconnectedContent: some View {
        Text("Your tasks stay in your folder. Connecting also keeps them in the cloud, so AI agents such as Claude can read and add tasks, and your devices stay in sync.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Button(isConnecting ? "Connecting…" : "Connect…") {
            isConnecting = true
            Task {
                await appState.connectCloudSync()
                isConnecting = false
            }
        }
        .disabled(isConnecting)
        .controlSize(.small)
        Text("Connecting switches file names to yyyy-MM-dd and times to 24-hour, and uploads your existing files.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var statusText: String {
        if cloudSync.isSyncing { return "Syncing…" }
        var parts: [String] = []
        if let lastSyncedAt = cloudSync.lastSyncedAt {
            parts.append("Synced \(lastSyncedAt.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("Not synced yet")
        }
        if cloudSync.pendingChanges > 0 {
            parts.append("\(cloudSync.pendingChanges) change(s) waiting")
        }
        return parts.joined(separator: " · ")
    }

    private func run(_ action: @escaping () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
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
                .font(.callout)
                .frame(width: 120, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
