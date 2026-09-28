import Foundation
import Testing
import QuickboxCore
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
        let line = writer.formattedLine(for: item, captureDate: date)
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
        var generatedIDs = ["aaaa1111", "bbbb2222"].makeIterator()
        let writer = InboxWriter(storageResolver: resolver, makeTaskID: { generatedIDs.next()! })

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
        #expect(content == "- [ ] 10:30 First id:aaaa1111\n- [ ] 10:31 Second id:bbbb2222\n")
    }

    @Test
    func projectEntriesAreStoredInDatedFilesInsideProjectDirectory() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        var generatedIDs = ["proj0001", "inbx0001"].makeIterator()
        let writer = InboxWriter(storageResolver: TestStorageResolver(baseURL: tempFolder), makeTaskID: { generatedIDs.next()! })

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 27
        components.hour = 10
        components.minute = 30
        let date = Calendar(identifier: .gregorian).date(from: components)!

        try writer.appendEntry("Ship release @alpha", now: date)
        try writer.appendEntry("Inbox note", now: date)

        let projectFileURL = tempFolder.appendingPathComponent("alpha/2026-02-27.md")
        #expect(try String(contentsOf: projectFileURL) == "- [ ] 10:30 Ship release @alpha id:proj0001\n")

        let dailyFileURL = tempFolder.appendingPathComponent("2026-02-27.md")
        #expect(try String(contentsOf: dailyFileURL) == "- [ ] 10:30 Inbox note id:inbx0001\n")
        #expect(!FileManager.default.fileExists(atPath: tempFolder.appendingPathComponent("alpha.md").path))
    }

    @Test
    func repositoryLoadsAndMutatesProjectDirectoryEntries() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let resolver = TestStorageResolver(baseURL: tempFolder)
        let writer = InboxWriter(storageResolver: resolver)
        let repository = InboxRepository(storageResolver: resolver)

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 27
        components.hour = 9
        components.minute = 0
        let date = Calendar(identifier: .gregorian).date(from: components)!

        try writer.appendEntry("Inbox note", now: date)
        try writer.appendEntry("Project task @alpha", now: date)

        let items = try repository.load(on: date)
        #expect(items.map(\.text).sorted() == ["Inbox note", "Project task"])

        let projectItem = try #require(items.first { $0.projectName == "alpha" })
        let updated = try repository.apply(.toggle(projectItem.id), on: date)
        #expect(updated.first { $0.projectName == "alpha" }?.isCompleted == true)

        let projectFileURL = tempFolder.appendingPathComponent("alpha/2026-02-27.md")
        #expect(try String(contentsOf: projectFileURL).hasPrefix("- [x] 09:00 Project task"))
    }

    @Test
    func repositoryMigratesLegacyFlatProjectFilesOnLoad() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        try "- [ ] 08:00 Old task @alpha date:2026-02-27\n- [x] 08:05 Other day @alpha #ops date:2026-02-28\n"
            .write(to: tempFolder.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)

        let repository = InboxRepository(storageResolver: TestStorageResolver(baseURL: tempFolder))

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 27
        let date = Calendar(identifier: .gregorian).date(from: components)!

        let items = try repository.load(on: date)
        #expect(items.map(\.text) == ["Old task"])
        #expect(items.first?.id.hasPrefix("alpha/2026-02-27.md#") == true)

        let alphaFolder = tempFolder.appendingPathComponent("alpha")
        #expect(try String(contentsOf: alphaFolder.appendingPathComponent("2026-02-27.md")) == "- [ ] 08:00 Old task @alpha\n")
        #expect(try String(contentsOf: alphaFolder.appendingPathComponent("2026-02-28.md")) == "- [x] 08:05 Other day @alpha #ops\n")
        #expect(!FileManager.default.fileExists(atPath: tempFolder.appendingPathComponent("alpha.md").path))
    }

    @Test
    func legacyMigrationKeepsUnroutableLinesAndSkipsDuplicates() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let alphaFolder = tempFolder.appendingPathComponent("alpha")
        try FileManager.default.createDirectory(at: alphaFolder, withIntermediateDirectories: true)
        let targetURL = alphaFolder.appendingPathComponent("2026-02-27.md")
        try "- [ ] 08:00 Old task @alpha\n".write(to: targetURL, atomically: true, encoding: .utf8)

        let legacyURL = tempFolder.appendingPathComponent("alpha.md")
        try "# Notes\n- [ ] 08:00 Old task @alpha date:2026-02-27\n- [ ] 09:00 Untagged @alpha\n"
            .write(to: legacyURL, atomically: true, encoding: .utf8)

        try LegacyProjectMigrator().migrate(in: tempFolder)

        #expect(try String(contentsOf: targetURL) == "- [ ] 08:00 Old task @alpha\n")
        #expect(try String(contentsOf: legacyURL) == "# Notes\n- [ ] 09:00 Untagged @alpha\n")
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
            crashReportingEnabled: true
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
            crashReportingEnabled: false
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
    func repositoryEditPreservesMetadataTokens() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let resolver = TestStorageResolver(baseURL: tempFolder)
        let repository = InboxRepository(storageResolver: resolver)

        let fileURL = tempFolder.appendingPathComponent(todayFileName(for: Date()))
        try "- [ ] 08:00 first due:next friday start:in 2 days time:30m\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let items = try repository.loadToday()
        let item = try #require(items.first)

        _ = try repository.apply(.edit(item.id, text: "first updated"))
        let fileAfterEdit = try String(contentsOf: fileURL)

        #expect(fileAfterEdit.contains("due:next friday"))
        #expect(fileAfterEdit.contains("start:in 2 days"))
        #expect(fileAfterEdit.contains("time:30m"))
    }

    @Test
    func appendKeepsExplicitTaskIDInsteadOfGeneratingOne() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        var prefs = AppPreferences.default
        prefs.storageBookmarkData = nil
        prefs.fallbackStoragePath = tempFolder.path
        let writer = InboxWriter(
            storageResolver: StorageAccessManager(preferences: prefs),
            makeTaskID: { Issue.record("An explicit id must not be replaced"); return "unused" }
        )

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 27
        components.hour = 10
        components.minute = 30
        let date = Calendar(identifier: .gregorian).date(from: components)!

        try writer.appendEntry("Publish post id:post42 @Marketing", now: date)

        let content = try String(contentsOf: tempFolder.appendingPathComponent("Marketing/2026-02-27.md"))
        #expect(content == "- [ ] 10:30 Publish post @Marketing id:post42\n")
    }

    @Test
    func repositoryMutatesByTaskIDAfterFileChangedUnderneath() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let repository = InboxRepository(storageResolver: TestStorageResolver(baseURL: tempFolder))
        let fileURL = tempFolder.appendingPathComponent(todayFileName(for: Date()))
        try "- [ ] 08:00 first id:first001\n- [ ] 09:00 second id:second02\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let items = try repository.loadToday()
        let second = try #require(items.first(where: { $0.taskID == "second02" }))

        // Simulate another writer (sync, agent) inserting a line above the item after it was loaded.
        try "- [ ] 07:00 from agent id:agent003\n- [ ] 08:00 first id:first001\n- [ ] 09:00 second id:second02\n"
            .write(to: fileURL, atomically: true, encoding: .utf8)

        _ = try repository.apply(.toggle(second.id))

        let content = try String(contentsOf: fileURL)
        #expect(content.contains("- [x] 09:00 second id:second02"))
        #expect(content.contains("- [ ] 08:00 first id:first001"))
        #expect(content.contains("- [ ] 07:00 from agent id:agent003"))
    }

    @Test
    func repositoryEditPreservesTaskID() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let repository = InboxRepository(storageResolver: TestStorageResolver(baseURL: tempFolder))
        let fileURL = tempFolder.appendingPathComponent(todayFileName(for: Date()))
        try "- [ ] 08:00 first #tag id:keepme01\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let item = try #require(try repository.loadToday().first)
        let updated = try repository.apply(.edit(item.id, text: "first updated"))

        let content = try String(contentsOf: fileURL)
        #expect(content == "- [ ] 08:00 first updated #tag id:keepme01\n")
        #expect(updated.first?.id == item.id)
    }

    @Test
    func repositorySetMetadataReplacesOnlyThatToken() throws {
        let (repository, fileURL, cleanup) = try makeRepositoryWithTodayFile(
            "- [ ] 08:00 Draft !2 #social time:30m remind:1h id:meta0001\n"
        )
        defer { cleanup() }

        let item = try #require(try repository.loadToday().first)
        let updated = try repository.apply(.setMetadata(item.id, key: "time", value: "1h"))

        #expect(try String(contentsOf: fileURL) == "- [ ] 08:00 Draft !2 #social remind:1h time:1h id:meta0001\n")
        #expect(updated.first?.metadata == ["time": "1h", "remind": "1h"])
    }

    @Test
    func repositorySetMetadataWithNilRemovesToken() throws {
        let (repository, fileURL, cleanup) = try makeRepositoryWithTodayFile("- [x] 08:00 Draft time:30m for:agent id:meta0002\n")
        defer { cleanup() }

        let item = try #require(try repository.loadToday().first)
        _ = try repository.apply(.setMetadata(item.id, key: "time", value: nil))

        #expect(try String(contentsOf: fileURL) == "- [x] 08:00 Draft for:agent id:meta0002\n")
    }

    @Test
    func repositorySetMetadataKeepsTaskIDThroughLegacyProjectMigration() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let today = todayFileName(for: Date()).replacingOccurrences(of: ".md", with: "")
        let legacyURL = tempFolder.appendingPathComponent("Marketing.md")
        try "- [ ] 08:00 Post @Marketing due:2026-09-28 date:\(today) id:meta0003\n".write(to: legacyURL, atomically: true, encoding: .utf8)

        // Loading migrates the flat project file into Marketing/<today>.md; the id survives the move.
        let repository = InboxRepository(storageResolver: TestStorageResolver(baseURL: tempFolder))
        let item = try #require(try repository.loadToday().first)
        _ = try repository.apply(.setMetadata(item.id, key: "due", value: "2026-09-30"))

        let migratedURL = tempFolder.appendingPathComponent("Marketing/\(today).md")
        #expect(item.id == "Marketing/\(today).md#id:meta0003")
        #expect(try String(contentsOf: migratedURL) == "- [ ] 08:00 Post @Marketing due:2026-09-30 id:meta0003\n")
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test
    func repositorySetMetadataRejectsReservedKeys() throws {
        let (repository, fileURL, cleanup) = try makeRepositoryWithTodayFile("- [ ] 08:00 Draft id:meta0004\n")
        defer { cleanup() }

        let item = try #require(try repository.loadToday().first)
        #expect(throws: InboxRepositoryError.reservedMetadataKey) {
            try repository.apply(.setMetadata(item.id, key: "id", value: "hijack"))
        }
        #expect(try String(contentsOf: fileURL) == "- [ ] 08:00 Draft id:meta0004\n")
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
    func selectInboxDateLoadsInboxForChosenDay() throws {
        let repository = TestRepository()
        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: repository
        )
        appState.prepareSpotlightSession()
        let initialLoadCount = repository.loadCallCount

        let calendar = Calendar(identifier: .gregorian)
        let target = try #require(calendar.date(byAdding: .day, value: -3, to: appState.selectedInboxDate))

        appState.selectInboxDate(target)

        #expect(calendar.startOfDay(for: appState.selectedInboxDate) == calendar.startOfDay(for: target))
        #expect(repository.loadCallCount == initialLoadCount + 1)
        let lastLoadedDate = try #require(repository.lastLoadedDate)
        #expect(calendar.startOfDay(for: lastLoadedDate) == calendar.startOfDay(for: target))
    }

    @MainActor
    @Test
    func selectInboxDateSameDayDoesNotReload() {
        let repository = TestRepository()
        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: repository
        )
        appState.prepareSpotlightSession()
        let initialLoadCount = repository.loadCallCount

        appState.selectInboxDate(appState.selectedInboxDate)

        #expect(repository.loadCallCount == initialLoadCount)
    }

    @MainActor
    @Test
    func loadCalendarIndicatorsCachesByDayAndRespectsForceReload() async throws {
        let repository = TestRepository()
        let calendar = Calendar(identifier: .gregorian)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 10, minute: 0)))
        let day1 = calendar.startOfDay(for: start)
        let day2 = try #require(calendar.date(byAdding: .day, value: 1, to: day1))
        let day3 = try #require(calendar.date(byAdding: .day, value: 2, to: day1))
        repository.itemsByDate[day1] = [sampleItem(id: "day1", priority: 1)]
        repository.itemsByDate[day2] = [sampleItem(id: "day2", priority: 2)]
        repository.itemsByDate[day3] = [sampleItem(id: "day3", priority: 3)]

        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: repository
        )

        // Wait for the indicators to be applied, not just for the repository calls: results reach the
        // main actor a step later, and a second request in between would legitimately reload.
        appState.loadCalendarIndicators(from: start, to: day3)
        try await waitUntil("initial indicator load") {
            [day1, day2, day3].allSatisfy { appState.calendarDayIndicators[$0] != nil }
        }
        #expect(repository.loadCallCount == 3)

        let cachedLoadCount = repository.loadCallCount
        appState.loadCalendarIndicators(from: start, to: day3)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(repository.loadCallCount == cachedLoadCount)

        appState.loadCalendarIndicators(from: start, to: day3, forceReload: true)
        try await waitUntil("force indicator reload") {
            repository.loadCallCount == cachedLoadCount + 3
                && [day1, day2, day3].allSatisfy { appState.calendarDayIndicators[$0] != nil }
        }
    }

    @MainActor
    @Test
    func loadCalendarIndicatorsNormalizesSameDayRange() async throws {
        let repository = TestRepository()
        let calendar = Calendar(identifier: .gregorian)
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 9, minute: 0)))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 22, minute: 30)))
        let normalized = calendar.startOfDay(for: morning)

        repository.itemsByDate[normalized] = [sampleItem(id: "same-day", priority: 2)]
        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: repository
        )

        appState.loadCalendarIndicators(from: morning, to: evening)
        try await waitUntil("same day indicator load") { appState.calendarDayIndicators[normalized] != nil }
        #expect(repository.loadCallCount == 1)
        #expect(appState.calendarDayIndicators[normalized]?.totalCount == 1)

        appState.loadCalendarIndicators(from: morning, to: evening)
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(repository.loadCallCount == 1)
    }

    @MainActor
    @Test
    func mutationUpdatesCalendarIndicatorForSelectedDay() {
        let repository = TestRepository()
        repository.items = [sampleItem(id: "a", priority: 1, completed: false)]
        repository.applyHandler = { mutation, currentItems in
            switch mutation {
            case .delete(let id):
                return currentItems.filter { $0.id != id }
            case .toggle(let id):
                return currentItems.map { item in
                    guard item.id == id else { return item }
                    return InboxItem(
                        id: item.id,
                        text: item.text,
                        tags: item.tags,
                        dueDate: item.dueDate,
                        priority: item.priority,
                        projectName: item.projectName,
                        metadata: item.metadata,
                        time: item.time,
                        isCompleted: !item.isCompleted,
                        lineIndex: item.lineIndex,
                        rawLine: item.rawLine
                    )
                }
            case .edit(let id, let text):
                return currentItems.map { item in
                    guard item.id == id else { return item }
                    return InboxItem(
                        id: item.id,
                        text: text,
                        tags: item.tags,
                        dueDate: item.dueDate,
                        priority: item.priority,
                        projectName: item.projectName,
                        metadata: item.metadata,
                        time: item.time,
                        isCompleted: item.isCompleted,
                        lineIndex: item.lineIndex,
                        rawLine: item.rawLine
                    )
                }
            case .undoLastDelete, .setMetadata:
                return currentItems
            }
        }

        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: repository
        )

        appState.prepareSpotlightSession()
        let selected = Calendar(identifier: .gregorian).startOfDay(for: appState.selectedInboxDate)
        #expect(appState.calendarDayIndicators[selected]?.totalCount == 1)

        appState.handleSpotlightMutation(.delete("a"))
        #expect(appState.calendarDayIndicators[selected] == nil)
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
    }

    @MainActor
    @Test
    func diagnosticsPreferencePropagatesToCrashReporter() {
        let crashReporter = TestCrashReporter()
        let appState = makeAppState(
            clipboard: { nil },
            writer: TestWriter(),
            repository: TestRepository(),
            crashReporter: crashReporter
        )

        appState.updateCrashReportingConsent(true)

        #expect(crashReporter.lastConsentValue == true)
        #expect(appState.preferences.crashReportingEnabled == true)
    }

    private func makeRepositoryWithTodayFile(_ content: String) throws -> (InboxRepository, URL, () -> Void) {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        let fileURL = tempFolder.appendingPathComponent(todayFileName(for: Date()))
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        let repository = InboxRepository(storageResolver: TestStorageResolver(baseURL: tempFolder))
        return (repository, fileURL, { try? FileManager.default.removeItem(at: tempFolder) })
    }

    private func todayFileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date) + ".md"
    }

    private func sampleItem(id: String, priority: Int? = nil, completed: Bool = false) -> InboxItem {
        InboxItem(
            id: id,
            text: "Task \(id)",
            dueDate: nil,
            priority: priority,
            metadata: [:],
            time: "10:00",
            isCompleted: completed,
            lineIndex: 0,
            rawLine: "- [ ] 10:00 Task \(id)"
        )
    }

    @MainActor
    private func waitUntil(
        _ label: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        checkEveryNanoseconds: UInt64 = 20_000_000,
        _ condition: @escaping () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: checkEveryNanoseconds)
        }
        #expect(Bool(false), "Timed out waiting for \(label)")
    }

    @MainActor
    private func makeAppState(
        clipboard: @escaping () -> String?,
        writer: InboxWriting,
        repository: InboxRepositorying,
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
    var itemsByDate: [Date: [InboxItem]] = [:]
    var reloadCallCount = 0
    var loadCallCount = 0
    var lastLoadedDate: Date?
    var applyHandler: ((InboxMutation, [InboxItem]) -> [InboxItem])?

    func load(on date: Date) throws -> [InboxItem] {
        loadCallCount += 1
        lastLoadedDate = date
        let normalized = Calendar(identifier: .gregorian).startOfDay(for: date)
        if let datedItems = itemsByDate[normalized] {
            return datedItems
        }
        return items
    }
    func apply(_ mutation: InboxMutation, on date: Date) throws -> [InboxItem] {
        if let applyHandler {
            items = applyHandler(mutation, items)
        }
        return items
    }
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
