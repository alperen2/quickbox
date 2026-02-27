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
            let items = try inboxRepository.loadToday()
            inboxItems = sorted(items)
            canUndoDelete = inboxRepository.canUndoDelete
            if inboxItems.isEmpty {
                inboxMessage = "No notes for today yet."
            } else {
                inboxMessage = nil
            }
        } catch {
            inboxMessage = error.localizedDescription
        }
    }

    func reloadInbox(silent: Bool = false) {
        do {
            let items = try inboxRepository.reload()
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

    func handleSpotlightMutation(_ mutation: InboxMutation) {
        switch mutation {
        case .toggle(let id):
            applyInboxMutation(.toggle(id), successMessage: nil)
        case .delete(let id):
            applyInboxMutation(.delete(id), successMessage: "Deleted. You can undo.")
        case .undoLastDelete:
            applyInboxMutation(.undoLastDelete, successMessage: "Restored")
        }
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
            let fileURL = folderURL.appendingPathComponent(todayFileName())
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

    private func applyInboxMutation(_ mutation: InboxMutation, successMessage: String?) {
        do {
            let updatedItems = try inboxRepository.apply(mutation)
            inboxItems = sorted(updatedItems)
            canUndoDelete = inboxRepository.canUndoDelete
            inboxMessage = successMessage
        } catch {
            inboxMessage = error.localizedDescription
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

    private func todayFileName() -> String {
        Self.fileNameFormatter.string(from: Date()) + ".md"
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
