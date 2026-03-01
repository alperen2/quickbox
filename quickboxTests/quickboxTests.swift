import Foundation
import Testing
@testable import quickbox

@MainActor
struct quickboxTests {

    @Test
    func fileNameUsesDailyMarkdownPattern() {
        let resolver = StorageAccessManager(preferences: .default)
        let writer = InboxWriter(storageResolver: resolver)

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 27
        components.hour = 9
        components.minute = 13
        let date = Calendar(identifier: .gregorian).date(from: components)!

        #expect(writer.fileName(for: date) == "2026-02-27.md")
    }

    @Test
    func formattedLineMatchesTaskStyle() {
        let resolver = StorageAccessManager(preferences: .default)
        let writer = InboxWriter(storageResolver: resolver)

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 27
        components.hour = 18
        components.minute = 7
        let date = Calendar(identifier: .gregorian).date(from: components)!

        let item = InboxItem(
            id: UUID().uuidString,
            text: "Call designer",
            time: "18:07",
            isCompleted: false,
            lineIndex: 0,
            rawLine: ""
        )
        let line = writer.formattedLine(for: item, captureDate: date, routeDate: date, isProjectRoute: false)
        #expect(line == "- [ ] 18:07 Call designer")
    }

    @Test
    func fileNameUsesPrefixAndCustomDateFormat() {
        var preferences = AppPreferences.default
        preferences.fileDateFormat = "dd-MM-yyyy"
        preferences.fileNamePrefix = "qb-"
        let resolver = StorageAccessManager(preferences: preferences)
        let writer = InboxWriter(storageResolver: resolver)

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 27
        let date = Calendar(identifier: .gregorian).date(from: components)!

        #expect(writer.fileName(for: date) == "qb-27-02-2026.md")
    }

    @Test
    func appendCreatesAndExtendsDailyFile() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        var prefs = AppPreferences.default
        prefs.storageBookmarkData = nil
        prefs.fallbackStoragePath = tempFolder.path

        let resolver = StorageAccessManager(preferences: prefs)
        let writer = InboxWriter(storageResolver: resolver)

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 27
        components.hour = 10
        components.minute = 30
        let baseDate = Calendar(identifier: .gregorian).date(from: components)!

        try writer.appendEntry("First", now: baseDate)

        components.minute = 31
        let secondDate = Calendar(identifier: .gregorian).date(from: components)!
        try writer.appendEntry("Second", now: secondDate)

        let fileURL = tempFolder.appendingPathComponent("2026-02-27.md")
        let content = try String(contentsOf: fileURL)
        #expect(content == "- [ ] 10:30 First\n- [ ] 10:31 Second\n")
    }

    @Test
    func settingsStoreRoundTrip() {
        let suiteName = "quickbox.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(userDefaults: defaults)
        let expected = AppPreferences(
            shortcutKey: "command+shift+i",
            afterSaveMode: .keepOpen,
            storageBookmarkData: Data([1, 2, 3]),
            fallbackStoragePath: "/tmp/quickbox",
            launchAtLogin: true,
            fileDateFormat: "dd-MM-yyyy",
            timeFormat: "hh:mm a",
            fileNamePrefix: "qb-",
            crashReportingEnabled: true,
            autoUpdateEnabled: false,
            betaChannelEnabled: true
        )

        store.save(expected)
        let loaded = store.load()

        #expect(loaded.shortcutKey == expected.shortcutKey)
        #expect(loaded.afterSaveMode == expected.afterSaveMode)
        #expect(loaded.storageBookmarkData == expected.storageBookmarkData)
        #expect(loaded.fallbackStoragePath == expected.fallbackStoragePath)
        #expect(loaded.launchAtLogin == expected.launchAtLogin)
        #expect(loaded.fileDateFormat == expected.fileDateFormat)
        #expect(loaded.timeFormat == expected.timeFormat)
        #expect(loaded.fileNamePrefix == expected.fileNamePrefix)
        #expect(loaded.crashReportingEnabled == expected.crashReportingEnabled)
        #expect(loaded.autoUpdateEnabled == expected.autoUpdateEnabled)
        #expect(loaded.betaChannelEnabled == expected.betaChannelEnabled)
    }

    @Test
    func settingsStoreFallsBackOnCorruptData() {
        let suiteName = "quickbox.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(Data([0xFF, 0xAA]), forKey: "quickbox.preferences")
        let store = SettingsStore(userDefaults: defaults)

        let loaded = store.load()
        #expect(loaded.shortcutKey == AppPreferences.default.shortcutKey)
    }

    @Test
    func storageResolverThrowsForInvalidBookmark() {
        let preferences = AppPreferences(
            shortcutKey: AppPreferences.default.shortcutKey,
            afterSaveMode: .close,
            storageBookmarkData: Data([1, 2, 3]),
            fallbackStoragePath: "/tmp",
            launchAtLogin: false,
            fileDateFormat: AppPreferences.defaultFileDateFormat,
            timeFormat: AppPreferences.defaultTimeFormat,
            fileNamePrefix: "",
            crashReportingEnabled: false,
            autoUpdateEnabled: true,
            betaChannelEnabled: true
        )

        let resolver = StorageAccessManager(preferences: preferences)

        do {
            _ = try resolver.resolvedBaseURL()
            #expect(Bool(false), "Expected invalidBookmark error")
        } catch let error as StorageAccessError {
            #expect(error == .invalidBookmark)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test
    func writerMapsStorageFailuresToUserFriendlyErrors() {
        let invalidBookmarkWriter = InboxWriter(
            storageResolver: ThrowingStorageResolver(error: StorageAccessError.invalidBookmark)
        )
        do {
            try invalidBookmarkWriter.appendEntry("x", now: Date())
            #expect(Bool(false), "Expected storage unavailable error")
        } catch let error as InboxWriterError {
            #expect(error == .storageUnavailable)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }

        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolver = TestStorageResolver(baseURL: tempFolder)

        let permissionWriter = InboxWriter(
            storageResolver: resolver,
            fileManager: FailingFileManager(errorCode: NSFileWriteNoPermissionError)
        )
        do {
            try permissionWriter.appendEntry("x", now: Date())
            #expect(Bool(false), "Expected permission denied error")
        } catch let error as InboxWriterError {
            #expect(error == .permissionDenied)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }

        let diskWriter = InboxWriter(
            storageResolver: resolver,
            fileManager: FailingFileManager(errorCode: NSFileWriteOutOfSpaceError)
        )
        do {
            try diskWriter.appendEntry("x", now: Date())
            #expect(Bool(false), "Expected disk full error")
        } catch let error as InboxWriterError {
            #expect(error == .diskFull)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test
    func repositoryMapsStorageFailuresToUserFriendlyErrors() {
        let invalidBookmarkRepository = InboxRepository(
            storageResolver: ThrowingStorageResolver(error: StorageAccessError.invalidBookmark)
        )
        do {
            _ = try invalidBookmarkRepository.loadToday()
            #expect(Bool(false), "Expected storage unavailable error")
        } catch let error as InboxRepositoryError {
            #expect(error == .storageUnavailable)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }

        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolver = TestStorageResolver(baseURL: tempFolder)

        let permissionRepository = InboxRepository(
            storageResolver: resolver,
            fileManager: FailingFileManager(errorCode: NSFileReadNoPermissionError)
        )
        do {
            _ = try permissionRepository.loadToday()
            #expect(Bool(false), "Expected permission denied error")
        } catch let error as InboxRepositoryError {
            #expect(error == .permissionDenied)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }

        let diskRepository = InboxRepository(
            storageResolver: resolver,
            fileManager: FailingFileManager(errorCode: NSFileWriteOutOfSpaceError)
        )
        do {
            _ = try diskRepository.loadToday()
            #expect(Bool(false), "Expected disk full error")
        } catch let error as InboxRepositoryError {
            #expect(error == .diskFull)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test
    func parserReturnsOnlyValidTaskLines() {
        let parser = InboxParser()
        let lines = [
            "- [ ] 09:10 plan sprint",
            "random line",
            "- [x] 09:20 done item"
        ]

        let items = parser.parse(lines: lines, sourceID: "today.md")
        #expect(items.count == 2)
        #expect(items[0].isCompleted == false)
        #expect(items[1].isCompleted == true)
        #expect(items[0].lineIndex == 0)
        #expect(items[1].lineIndex == 2)
    }

    @Test
    func repositoryToggleDeleteUndoFlow() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let resolver = TestStorageResolver(baseURL: tempFolder)
        let repository = InboxRepository(storageResolver: resolver)

        let fileURL = tempFolder.appendingPathComponent(todayFileName(for: Date()))
        try "- [ ] 08:00 first\n- [ ] 09:00 second\n".write(to: fileURL, atomically: true, encoding: .utf8)

        var items = try repository.loadToday()
        #expect(items.count == 2)

        items = try repository.apply(.toggle(items[0].id))
        let fileAfterToggle = try String(contentsOf: fileURL)
        #expect(fileAfterToggle.contains("- [x] 08:00 first"))

        let firstItem = try #require(items.first(where: { $0.text == "first" }))
        items = try repository.apply(.edit(firstItem.id, text: "first updated"))
        let fileAfterEdit = try String(contentsOf: fileURL)
        #expect(fileAfterEdit.contains("- [x] 08:00 first updated"))

        let secondItem = try #require(items.first(where: { $0.text == "second" }))
        _ = try repository.apply(.delete(secondItem.id))
        let fileAfterDelete = try String(contentsOf: fileURL)
        #expect(!fileAfterDelete.contains("second"))
        #expect(repository.canUndoDelete)

        _ = try repository.apply(.undoLastDelete)
        let fileAfterUndo = try String(contentsOf: fileURL)
        #expect(fileAfterUndo.contains("second"))
        #expect(!repository.canUndoDelete)
    }

    @Test
    func repositoryHandlesMissingDailyFile() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let resolver = TestStorageResolver(baseURL: tempFolder)
        let repository = InboxRepository(storageResolver: resolver)

        let items = try repository.loadToday()
        #expect(items.isEmpty)
    }

    @MainActor
    @Test
    func clipboardPrefillUsesValidClipboardText() {
        let appState = makeAppState(
            clipboard: { "Plan release checklist" },
            writer: TestWriter(),
            repository: TestRepository()
        )

        appState.clearCaptureStateForPresentation()
        appState.prepareCaptureDraftFromClipboardIfNeeded()

        #expect(appState.draftText == "Plan release checklist")
    }

    @MainActor
    @Test
    func clipboardPrefillSkipsWhitespaceAndLongText() {
        let longText = String(repeating: "a", count: 501)
        let appStateWhitespace = makeAppState(
            clipboard: { "   \n   " },
            writer: TestWriter(),
            repository: TestRepository()
        )
        appStateWhitespace.clearCaptureStateForPresentation()
        appStateWhitespace.prepareCaptureDraftFromClipboardIfNeeded()
        #expect(appStateWhitespace.draftText.isEmpty)

        let appStateLong = makeAppState(
            clipboard: { longText },
            writer: TestWriter(),
            repository: TestRepository()
        )
        appStateLong.clearCaptureStateForPresentation()
        appStateLong.prepareCaptureDraftFromClipboardIfNeeded()
        #expect(appStateLong.draftText.isEmpty)
    }

    @MainActor
    @Test
    func submitCaptureFromSpotlightReturnsKeepOpenAndClearsDraft() {
        let writer = TestWriter()
        let repository = TestRepository()
        let appState = makeAppState(
            clipboard: { nil },
            writer: writer,
            repository: repository
        )
        appState.draftText = "Ship update"

        let result = appState.submitCaptureFromSpotlight()

        #expect(result == .savedKeepOpen)
        #expect(appState.draftText.isEmpty)
        #expect(repository.reloadCallCount == 1)
        #expect(appState.captureMessage == nil)
    }

    @MainActor
    @Test
    func submitCaptureFailureKeepsDraft() {
        let writer = TestWriter()
        writer.shouldThrow = true
        let appState = makeAppState(
            clipboard: { nil },
            writer: writer,
            repository: TestRepository()
        )
        appState.draftText = "Keep draft on error"

        let result = appState.submitCapture()

        #expect(result == .failed)
        #expect(appState.draftText == "Keep draft on error")
    }

    @MainActor
    @Test
    func prepareSpotlightSessionClearsDraftAndLoadsInbox() {
        let repository = TestRepository()
        repository.items = [
            InboxItem(
                id: "a",
                text: "task",
                time: "10:00",
                isCompleted: false,
                lineIndex: 0,
                rawLine: "- [ ] 10:00 task"
            )
        ]
        let appState = makeAppState(
            clipboard: { "Call PM" },
            writer: TestWriter(),
            repository: repository
        )

        appState.prepareSpotlightSession()

        #expect(appState.isSpotlightModeActive)
        #expect(appState.draftText.isEmpty)
        #expect(appState.inboxItems.count == 1)
    }

    @MainActor
    @Test
    func dayNavigationChangesLabelAndStopsAtToday() {
        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: TestRepository()
        )

        appState.prepareSpotlightSession()
        #expect(appState.selectedInboxDateLabel == "Today")
        #expect(appState.canNavigateForwardInboxDate)

        appState.navigateInboxDayBackward()
        #expect(appState.selectedInboxDateLabel == "Yesterday")
        #expect(appState.canNavigateForwardInboxDate)

        appState.navigateInboxDayBackward()
        #expect(appState.selectedInboxDateLabel.contains("-"))

        appState.navigateInboxDayForward()
        #expect(appState.selectedInboxDateLabel == "Yesterday")
        appState.navigateInboxDayForward()
        #expect(appState.selectedInboxDateLabel == "Today")
        appState.navigateInboxDayForward()
        #expect(appState.selectedInboxDateLabel == "Tomorrow")
        #expect(appState.canNavigateForwardInboxDate)
    }

    @MainActor
    @Test
    func formatUpdatesChangePreviewAndValidateInput() {
        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: TestRepository()
        )

        appState.updateFileNamePrefix("qb/")
        appState.updateFileDateFormat("dd-MM-yyyy")
        appState.updateTimeFormat("hh:mm a")

        #expect(appState.settingsPreviewFileName.hasPrefix("qb-"))
        #expect(appState.settingsPreviewFileName.hasSuffix(".md"))
        #expect(appState.settingsPreviewLine.contains("Example task"))

        let previousFormat = appState.preferences.fileDateFormat
        appState.updateFileDateFormat("invalid-format")
        #expect(appState.preferences.fileDateFormat == previousFormat)
        #expect(appState.settingsMessage == "Invalid date format.")
    }

    @Test
    func appPreferencesLegacyDecodeGetsDiagnosticsDefaults() throws {
        let legacyJSON = """
        {
          "shortcutKey": "command+shift+space",
          "afterSaveMode": "close",
          "storageBookmarkData": null,
          "fallbackStoragePath": "/tmp/quickbox",
          "launchAtLogin": false,
          "fileDateFormat": "yyyy-MM-dd",
          "timeFormat": "HH:mm",
          "fileNamePrefix": ""
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppPreferences.self, from: legacyJSON)
        #expect(decoded.crashReportingEnabled == false)
        #expect(decoded.autoUpdateEnabled == true)
        #expect(decoded.betaChannelEnabled == true)
    }

    @MainActor
    @Test
    func diagnosticsAndUpdatePreferencesPropagateToManagers() {
        let updateManager = TestUpdateManager()
        let crashReporter = TestCrashReporter()
        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: TestRepository(),
            updateManager: updateManager,
            crashReporter: crashReporter
        )

        appState.updateAutoUpdate(false)
        appState.updateCrashReportingConsent(true)
        appState.updateBetaChannelEnabled(false)

        #expect(updateManager.lastSetAutoCheck == false)
        #expect(updateManager.lastSetBetaChannel == false)
        #expect(crashReporter.lastConsentValue == true)
        #expect(appState.preferences.autoUpdateEnabled == false)
        #expect(appState.preferences.crashReportingEnabled == true)
        #expect(appState.preferences.betaChannelEnabled == false)
    }

    private func todayFileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date) + ".md"
    }

    @MainActor
    private func makeAppState(
        clipboard: @escaping () -> String?,
        writer: InboxWriting,
        repository: InboxRepositorying,
        updateManager: UpdateManaging? = nil,
        crashReporter: CrashReporting? = nil
    ) -> AppState {
        let suiteName = "quickbox.tests.state.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(userDefaults: defaults)
        return AppState(
            settingsStore: settingsStore,
            hotkeyManager: HotkeyManager(),
            inboxWriter: writer,
            inboxRepository: repository,
            updateManager: updateManager,
            crashReporter: crashReporter,
            clipboardProvider: clipboard,
            registerHotkeyOnInit: false,
            loadInboxOnInit: false
        )
    }
}

private struct TestStorageResolver: StorageResolving {
    let baseURL: URL

    func resolvedBaseURL() throws -> URL {
        baseURL
    }

    func stopAccess(for url: URL) {
        _ = url
    }
}

private struct ThrowingStorageResolver: StorageResolving {
    let error: Error

    func resolvedBaseURL() throws -> URL {
        throw error
    }

    func stopAccess(for url: URL) {
        _ = url
    }
}

private final class FailingFileManager: FileManager {
    private let error: NSError

    init(errorCode: Int) {
        self.error = NSError(domain: NSCocoaErrorDomain, code: errorCode, userInfo: nil)
        super.init()
    }

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        throw error
    }
}

private final class TestWriter: InboxWriting {
    var shouldThrow = false

    func appendEntry(_ text: String, now: Date) throws {
        if shouldThrow {
            throw InboxWriterError.emptyEntry
        }
    }
}

private final class TestRepository: InboxRepositorying, @unchecked Sendable {
    var canUndoDelete: Bool = false
    var items: [InboxItem] = []
    var reloadCallCount = 0

    func load(on date: Date) throws -> [InboxItem] { items }
    func apply(_ mutation: InboxMutation, on date: Date) throws -> [InboxItem] { items }
    func reload(on date: Date) throws -> [InboxItem] {
        reloadCallCount += 1
        return items
    }
    func loadToday() throws -> [InboxItem] { items }
    func apply(_ mutation: InboxMutation) throws -> [InboxItem] { items }
    func reload() throws -> [InboxItem] {
        reloadCallCount += 1
        return items
    }
}

private final class TestUpdateManager: UpdateManaging {
    private(set) var didStart = false
    private(set) var didCheckUpdates = false
    private(set) var lastSetAutoCheck: Bool?
    private(set) var lastSetBetaChannel: Bool?

    func start() {
        didStart = true
    }

    func checkForUpdates() throws {
        didCheckUpdates = true
    }

    func setAutoCheck(_ enabled: Bool) {
        lastSetAutoCheck = enabled
    }

    func setBetaChannel(_ enabled: Bool) {
        lastSetBetaChannel = enabled
    }
}

private final class TestCrashReporter: CrashReporting {
    private(set) var lastConsentValue: Bool?
    private(set) var eventCount = 0

    func setConsent(_ enabled: Bool) {
        lastConsentValue = enabled
    }

    func record(nonFatal error: Error, errorContext: [String : String]) {
        _ = error
        _ = errorContext
        eventCount += 1
    }
}
