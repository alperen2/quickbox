import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    enum SubmitResult {
        case savedAndClose
        case savedKeepOpen
        case failed
    }

    @Published var preferences: AppPreferences
    @Published var draftText: String = ""
    @Published var captureMessage: String?
    @Published var settingsMessage: String?
    @Published var inboxItems: [InboxItem] = []
    @Published var inboxMessage: String?
    @Published var selectedInboxDate: Date = Calendar(identifier: .gregorian).startOfDay(for: Date())
    @Published var canUndoDelete: Bool = false
    @Published var showOnlyOpenTasks: Bool = false
    @Published var isSpotlightModeActive: Bool = false

    private let settingsStore: SettingsStore
    private let hotkeyManager: HotkeyManager
    private let storageAccessManager: StorageAccessManager
    private let inboxWriter: InboxWriting
    private let inboxRepository: InboxRepositorying
    private let clipboardProvider: () -> String?

    var onCaptureRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?
    var onCaptureSaved: (() -> Void)?

    init(
        settingsStore: SettingsStore,
        hotkeyManager: HotkeyManager,
        storageAccessManager: StorageAccessManager? = nil,
        inboxWriter: InboxWriting? = nil,
        inboxRepository: InboxRepositorying? = nil,
        clipboardProvider: @escaping () -> String? = {
            NSPasteboard.general.string(forType: .string)
        },
        registerHotkeyOnInit: Bool = true,
        loadInboxOnInit: Bool = true
    ) {
        self.settingsStore = settingsStore
        self.hotkeyManager = hotkeyManager
        self.clipboardProvider = clipboardProvider

        let loadedPreferences = settingsStore.load()
        self.preferences = loadedPreferences

        let storageAccessManager = storageAccessManager ?? StorageAccessManager(preferences: loadedPreferences)
        self.storageAccessManager = storageAccessManager
        self.inboxWriter = inboxWriter ?? InboxWriter(storageResolver: storageAccessManager)
        self.inboxRepository = inboxRepository ?? InboxRepository(storageResolver: storageAccessManager)

        hotkeyManager.onHotKey = { [weak self] in
            DispatchQueue.main.async {
                self?.onCaptureRequested?()
            }
        }

        if registerHotkeyOnInit {
            applyHotkeyFromPreferences()
            if preferences.launchAtLogin {
                applyLaunchAtLogin(true)
            }
        }

        if loadInboxOnInit {
            loadInbox()
        }
    }

    var currentStoragePath: String {
        if let bookmarkData = preferences.storageBookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url.path
            }
        }

        return preferences.fallbackStoragePath
    }

    var visibleInboxItems: [InboxItem] {
        if showOnlyOpenTasks {
            return inboxItems.filter { !$0.isCompleted }
        }
        return inboxItems
    }

    var selectedInboxDateLabel: String {
        let selected = Self.calendar.startOfDay(for: selectedInboxDate)
        let today = Self.calendar.startOfDay(for: Date())
        if selected == today {
            return "Today"
        }
        if let yesterday = Self.calendar.date(byAdding: .day, value: -1, to: today), selected == yesterday {
            return "Yesterday"
        }
        return FormatSettings.dateLabel(for: selected, preferences: preferences)
    }

    var canNavigateForwardInboxDate: Bool {
        Self.calendar.startOfDay(for: selectedInboxDate) < Self.calendar.startOfDay(for: Date())
    }

    var settingsPreviewFileName: String {
        FormatSettings.fileName(for: Date(), preferences: preferences)
    }

    var settingsPreviewLine: String {
        let time = FormatSettings.timeText(for: Date(), preferences: preferences)
        return "- [ ] \(time) Example task"
    }

    func submitCapture() -> SubmitResult {
        do {
            try inboxWriter.appendEntry(draftText, now: Date())
            draftText = ""
            captureMessage = "Saved"
            reloadInbox(silent: true)
            onCaptureSaved?()
            return .savedAndClose
        } catch {
            captureMessage = error.localizedDescription
            return .failed
        }
    }

    func submitCaptureFromSpotlight() -> SubmitResult {
        do {
            try inboxWriter.appendEntry(draftText, now: Date())
            draftText = ""
            captureMessage = nil
            refreshSpotlightListAfterMutation()
            return .savedKeepOpen
        } catch {
            captureMessage = error.localizedDescription
            return .failed
        }
    }

    func clearCaptureStateForPresentation() {
        draftText = ""
        captureMessage = nil
    }

    func prepareSpotlightSession() {
        isSpotlightModeActive = true
        clearCaptureStateForPresentation()
        selectedInboxDate = Self.calendar.startOfDay(for: Date())
        loadTodayForSpotlight()
    }

    func endSpotlightSession() {
        isSpotlightModeActive = false
        captureMessage = nil
    }

    func loadTodayForSpotlight() {
        loadInbox()
    }

    func refreshSpotlightListAfterMutation() {
        reloadInbox(silent: true)
    }

    func prepareCaptureDraftFromClipboardIfNeeded() {
        guard let clipboardText = clipboardProvider() else {
            return
        }

        let cleaned = clipboardText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        guard !cleaned.isEmpty, cleaned.count <= 500 else {
            return
        }

        draftText = cleaned
    }

    func loadInbox() {
        do {
            let items = try inboxRepository.load(on: selectedInboxDate)
            inboxItems = sorted(items)
            canUndoDelete = inboxRepository.canUndoDelete
            if inboxItems.isEmpty {
                inboxMessage = "No notes for selected day."
            } else {
                inboxMessage = nil
            }
        } catch {
            inboxMessage = error.localizedDescription
        }
    }

    func reloadInbox(silent: Bool = false) {
        do {
            let items = try inboxRepository.reload(on: selectedInboxDate)
            inboxItems = sorted(items)
            canUndoDelete = inboxRepository.canUndoDelete
            if !silent {
                inboxMessage = "Reloaded"
            }
        } catch {
            inboxMessage = error.localizedDescription
        }
    }

    func toggleInboxItem(id: String) {
        applyInboxMutation(.toggle(id), successMessage: nil)
    }

    func deleteInboxItem(id: String) {
        applyInboxMutation(.delete(id), successMessage: "Deleted. You can undo.")
    }

    func undoDelete() {
        applyInboxMutation(.undoLastDelete, successMessage: "Restored")
    }

    @discardableResult
    func editInboxItem(id: String, text: String) -> Bool {
        applyInboxMutation(.edit(id, text: text), successMessage: nil)
    }

    func handleSpotlightMutation(_ mutation: InboxMutation) {
        switch mutation {
        case .toggle(let id):
            applyInboxMutation(.toggle(id), successMessage: nil)
        case .delete(let id):
            applyInboxMutation(.delete(id), successMessage: "Deleted. You can undo.")
        case .edit(let id, text: let text):
            applyInboxMutation(.edit(id, text: text), successMessage: nil)
        case .undoLastDelete:
            applyInboxMutation(.undoLastDelete, successMessage: "Restored")
        }
    }

    func navigateInboxDayBackward() {
        guard let previous = Self.calendar.date(byAdding: .day, value: -1, to: selectedInboxDate) else {
            return
        }
        selectedInboxDate = Self.calendar.startOfDay(for: previous)
        loadInbox()
    }

    func navigateInboxDayForward() {
        guard canNavigateForwardInboxDate,
              let next = Self.calendar.date(byAdding: .day, value: 1, to: selectedInboxDate)
        else {
            return
        }

        let today = Self.calendar.startOfDay(for: Date())
        selectedInboxDate = min(Self.calendar.startOfDay(for: next), today)
        loadInbox()
    }

    func updateAfterSaveMode(_ mode: AfterSaveMode) {
        preferences.afterSaveMode = mode
        persistPreferences(message: "After-save mode updated.")
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        preferences.launchAtLogin = enabled
        applyLaunchAtLogin(enabled)
        persistPreferences(message: "Launch-at-login updated.")
    }

    func updateShortcut(_ rawValue: String) {
        guard let combo = HotKeyCombo.parse(rawValue) else {
            settingsMessage = "Shortcut format invalid. Example: control+option+space"
            return
        }

        updateShortcut(combo)
    }

    func updateShortcut(_ combo: HotKeyCombo) {

        do {
            try hotkeyManager.register(combo)
            preferences.shortcutKey = combo.normalizedString
            persistPreferences(message: "Shortcut updated.")
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func updateFileDateFormat(_ format: String) {
        guard FormatSettings.isValidDateFormat(format) else {
            settingsMessage = "Invalid date format."
            return
        }

        preferences.fileDateFormat = format.trimmingCharacters(in: .whitespacesAndNewlines)
        persistPreferences(message: "Date format updated.")
    }

    func updateTimeFormat(_ format: String) {
        guard FormatSettings.isValidTimeFormat(format) else {
            settingsMessage = "Invalid time format."
            return
        }

        preferences.timeFormat = format.trimmingCharacters(in: .whitespacesAndNewlines)
        persistPreferences(message: "Time format updated.")
    }

    func updateFileNamePrefix(_ prefix: String) {
        preferences.fileNamePrefix = FormatSettings.sanitizePrefix(prefix)
        persistPreferences(message: "File prefix updated.")
    }

    func resetPreferencesToDefaults() {
        let defaults = AppPreferences.default
        preferences = defaults
        storageAccessManager.preferences = defaults
        settingsStore.save(defaults)

        do {
            let combo = HotKeyCombo.parse(defaults.shortcutKey) ?? .default
            try hotkeyManager.register(combo)
        } catch {
            settingsMessage = "Settings reset, but shortcut registration failed: \(error.localizedDescription)"
            loadInbox()
            return
        }

        applyLaunchAtLogin(defaults.launchAtLogin)
        selectedInboxDate = Self.calendar.startOfDay(for: Date())
        loadInbox()
        settingsMessage = "Settings reset to defaults."
    }

    func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmark = try storageAccessManager.makeBookmarkData(for: url)
                preferences.storageBookmarkData = bookmark
                preferences.fallbackStoragePath = url.path
                persistPreferences(message: "Storage folder updated.")
                loadInbox()
            } catch {
                settingsMessage = "Could not store folder access. Please try another folder."
            }
        }
    }

    func openTodayFile() {
        do {
            let folderURL = try storageAccessManager.resolvedBaseURL()
            defer { storageAccessManager.stopAccess(for: folderURL) }

            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let fileURL = folderURL.appendingPathComponent(FormatSettings.fileName(for: Date(), preferences: preferences))
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try Data().write(to: fileURL, options: .atomic)
            }
            NSWorkspace.shared.open(fileURL)
        } catch {
            inboxMessage = error.localizedDescription
        }
    }

    func openInboxFolder() {
        do {
            let folderURL = try storageAccessManager.resolvedBaseURL()
            defer { storageAccessManager.stopAccess(for: folderURL) }
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folderURL)
        } catch {
            inboxMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func applyInboxMutation(_ mutation: InboxMutation, successMessage: String?) -> Bool {
        do {
            let updatedItems = try inboxRepository.apply(mutation, on: selectedInboxDate)
            inboxItems = sorted(updatedItems)
            canUndoDelete = inboxRepository.canUndoDelete
            inboxMessage = successMessage
            return true
        } catch {
            inboxMessage = error.localizedDescription
            return false
        }
    }

    private func sorted(_ items: [InboxItem]) -> [InboxItem] {
        items.sorted { lhs, rhs in
            lhs.lineIndex > rhs.lineIndex
        }
    }

    private func applyHotkeyFromPreferences() {
        let combo = HotKeyCombo.parse(preferences.shortcutKey) ?? .default
        do {
            try hotkeyManager.register(combo)
            preferences.shortcutKey = combo.normalizedString
            settingsStore.save(preferences)
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settingsMessage = "Launch-at-login setting failed: \(error.localizedDescription)"
        }
    }

    private func persistPreferences(message: String) {
        storageAccessManager.preferences = preferences
        settingsStore.save(preferences)
        settingsMessage = message
    }

    private static let calendar = Calendar(identifier: .gregorian)
}
