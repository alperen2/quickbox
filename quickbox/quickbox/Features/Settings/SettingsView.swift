import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    @State private var currentCombo: HotKeyCombo
    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        _currentCombo = State(initialValue: HotKeyCombo.parse(appState.preferences.shortcutKey) ?? .default)
    }

    var body: some View {
        Form {
            Section("Shortcut") {
                HStack {
                    Text("Current")
                    Spacer()
                    Text(currentCombo.displayString)
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Button(isRecordingShortcut ? "Press keys..." : "Record Shortcut") {
                        toggleShortcutRecording()
                    }

                    if isRecordingShortcut {
                        Button("Cancel") {
                            stopShortcutRecording()
                        }
                    }
                }

                Text("Press a key with at least one modifier (⌃⌥⇧⌘).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                HStack {
                    Text(appState.currentStoragePath)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                }

                Button("Choose Folder") {
                    appState.chooseStorageFolder()
                }
            }

            Section("Capture") {
                Picker("After Save", selection: Binding(
                    get: { appState.preferences.afterSaveMode },
                    set: { appState.updateAfterSaveMode($0) }
                )) {
                    ForEach(AfterSaveMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { appState.preferences.launchAtLogin },
                    set: { appState.updateLaunchAtLogin($0) }
                ))
            }

            if let message = appState.settingsMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
        .padding()
        .frame(width: 520, height: 360)
        .onDisappear {
            stopShortcutRecording()
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
}
