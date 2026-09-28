import Foundation
import QuickboxCore

enum InboxRepositoryError: LocalizedError, Equatable {
    case itemNotFound
    case nothingToUndo
    case emptyEditedText
    case reservedMetadataKey
    case permissionDenied
    case diskFull
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The selected item no longer exists."
        case .nothingToUndo:
            return "There is nothing to undo."
        case .emptyEditedText:
            return "Task text cannot be empty."
        case .reservedMetadataKey:
            return "This field is managed by \(Brand.name) and cannot be changed."
        case .permissionDenied:
            return "\(Brand.name) cannot write to the storage folder. Check folder permissions in Settings."
        case .diskFull:
            return "Your disk appears to be full. Free some space and try again."
        case .storageUnavailable:
            return "Storage is currently unavailable. Please reselect the folder in Settings."
        }
    }
}

final class InboxRepository: InboxRepositorying, @unchecked Sendable {
    var canUndoDelete: Bool {
        lastDeleted != nil
    }

    /// Keys whose tokens are owned by the storage layer (routing and identity), not by the user.
    private static let reservedMetadataKeys: Set<String> = [TaskIdentifier.metadataKey, "date"]

    private struct DeletedLine {
        let line: String
        let lineIndex: Int
        let sourceID: String
    }

    private let storageResolver: StorageResolving
    private let fileManager: FileManager
    private let parser = InboxParser()

    private var lastDeleted: DeletedLine?
    private var migratedFolderPaths = Set<String>()

    init(storageResolver: StorageResolving, fileManager: FileManager = .default) {
        self.storageResolver = storageResolver
        self.fileManager = fileManager
    }

    func load(on date: Date) throws -> [InboxItem] {
        do {
            return try InboxStorageQueue.shared.sync {
                try withResolvedFolder { folderURL in
                    let allItems = try collectItems(on: date, in: folderURL)
                    
                    // Filter out deferred tasks
                    // A task with a future `defer:` date shouldn't show up until that date arrives.
                    let deferResolver = DeferDateResolver()
                    let activeItems = allItems.filter { item in
                        if let deferStr = item.metadata["defer"], 
                           let deferDate = deferResolver.resolve(deferDateString: deferStr, from: Date()) {
                            // If the defer date is strictly greater than the viewing date, hide it.
                            // We normalize both to start of day to compare purely by date, not time.
                            let calendar = Calendar.current
                            let viewingStartOfDay = calendar.startOfDay(for: date)
                            let deferStartOfDay = calendar.startOfDay(for: deferDate)
                            return viewingStartOfDay >= deferStartOfDay
                        }
                        return true
                    }
                    
                    // Sort items by time, just in case they were appended out of order across files
                    return activeItems.sorted { $0.time < $1.time }
                }
            }
        } catch {
            throw mappedStorageError(error)
        }
    }

    func loadToday() throws -> [InboxItem] {
        try load(on: Date())
    }

    func reload(on date: Date) throws -> [InboxItem] {
        try load(on: date)
    }

    func reload() throws -> [InboxItem] {
        try load(on: Date())
    }

    func apply(_ mutation: InboxMutation, on date: Date) throws -> [InboxItem] {
        do {
            return try InboxStorageQueue.shared.sync {
                try withResolvedFolder { folderURL in
                    // First we need to extract the sourceID from the mutation to know which file to edit
                    let targetID: String
                    switch mutation {
                    case .toggle(let id), .delete(let id), .edit(let id, _), .setMetadata(let id, _, _):
                        targetID = id
                    case .undoLastDelete:
                        guard let deleted = lastDeleted else { throw InboxRepositoryError.nothingToUndo }
                        targetID = deleted.sourceID
                    }
                    
                    let targetSourceID = targetID.components(separatedBy: "#").first ?? fileName(for: date)
                    let fileURL = folderURL.appendingPathComponent(targetSourceID)
                    
                    var lines = try readLines(fileURL: fileURL)
                    let sourceID = targetSourceID

                    switch mutation {
                    case .toggle(let id):
                        let items = parser.parse(lines: lines, sourceID: sourceID)
                        guard let item = items.first(where: { $0.id == id }) else {
                            throw InboxRepositoryError.itemNotFound
                        }

                        var updated = item.rawLine
                        if item.isCompleted {
                            updated.replaceSubrange(updated.startIndex..<updated.index(updated.startIndex, offsetBy: 5), with: "- [ ]")
                        } else {
                            updated.replaceSubrange(updated.startIndex..<updated.index(updated.startIndex, offsetBy: 5), with: "- [x]")
                        }
                        lines[item.lineIndex] = updated

                    case .delete(let id):
                        let items = parser.parse(lines: lines, sourceID: sourceID)
                        guard let item = items.first(where: { $0.id == id }) else {
                            throw InboxRepositoryError.itemNotFound
                        }

                        lines.remove(at: item.lineIndex)
                        lastDeleted = DeletedLine(line: item.rawLine, lineIndex: item.lineIndex, sourceID: sourceID)

                    case .edit(let id, text: let text):
                        let items = parser.parse(lines: lines, sourceID: sourceID)
                        guard let item = items.first(where: { $0.id == id }) else {
                            throw InboxRepositoryError.itemNotFound
                        }

                        let normalizedText = normalizeToSingleLine(text)
                        guard !normalizedText.isEmpty else {
                            throw InboxRepositoryError.emptyEditedText
                        }

                        lines[item.lineIndex] = try rebuiltLine(for: item, text: normalizedText)

                    case .setMetadata(let id, key: let rawKey, value: let rawValue):
                        let items = parser.parse(lines: lines, sourceID: sourceID)
                        guard let item = items.first(where: { $0.id == id }) else {
                            throw InboxRepositoryError.itemNotFound
                        }

                        let key = rawKey.lowercased()
                        guard !Self.reservedMetadataKeys.contains(key) else {
                            throw InboxRepositoryError.reservedMetadataKey
                        }
                        let value = rawValue.map(normalizeToSingleLine).flatMap { $0.isEmpty ? nil : $0 }

                        lines[item.lineIndex] = try rebuiltLine(for: item, text: item.text) { parsed in
                            if key == "due" {
                                parsed.dueDate = value
                            } else {
                                parsed.metadata[key] = value
                            }
                        }

                    case .undoLastDelete:
                        guard let deleted = lastDeleted, deleted.sourceID == sourceID else {
                            throw InboxRepositoryError.nothingToUndo
                        }

                        let insertIndex = min(deleted.lineIndex, lines.count)
                        lines.insert(deleted.line, at: insertIndex)
                        lastDeleted = nil
                    }

                    try writeLines(lines, to: fileURL)
                    
                    // Return the fully refreshed view for this date across ALL files so UI updates correctly
                    return try collectItems(on: date, in: folderURL)
                }
            }
        } catch {
            throw mappedStorageError(error)
        }
    }

    func apply(_ mutation: InboxMutation) throws -> [InboxItem] {
        try apply(mutation, on: Date())
    }

    /// Gathers every item that belongs to `date`: the daily inbox file and each project's dated file.
    private func collectItems(on date: Date, in folderURL: URL) throws -> [InboxItem] {
        let layout = StorageLayout(preferences: currentPreferences(), fileManager: fileManager)
        let dailyFileName = try fileURL(for: date, in: folderURL).lastPathComponent
        try migrateLegacyProjectsIfNeeded(in: folderURL)

        var allItems = try parseItems(relativePath: dailyFileName, in: folderURL)
        for projectURL in try layout.projectDirectories(in: folderURL) {
            let relativePath = layout.relativePath(for: date, project: projectURL.lastPathComponent)
            allItems.append(contentsOf: try parseItems(relativePath: relativePath, in: folderURL))
        }

        return allItems.sorted { $0.time < $1.time }
    }

    /// Runs once per storage folder per session; the migration itself is idempotent.
    private func migrateLegacyProjectsIfNeeded(in folderURL: URL) throws {
        let folderPath = folderURL.standardizedFileURL.path
        guard !migratedFolderPaths.contains(folderPath) else { return }
        try LegacyProjectMigrator(fileManager: fileManager).migrate(in: folderURL)
        migratedFolderPaths.insert(folderPath)
    }

    private func parseItems(relativePath: String, in folderURL: URL) throws -> [InboxItem] {
        let lines = try readLines(fileURL: folderURL.appendingPathComponent(relativePath))
        return parser.parse(lines: lines, sourceID: relativePath)
    }

    private func fileURL(for date: Date, in folderURL: URL) throws -> URL {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        return folderURL.appendingPathComponent(fileName(for: date))
    }

    private func fileName(for date: Date) -> String {
        FormatSettings.fileName(for: date, preferences: currentPreferences())
    }

    private func currentPreferences() -> AppPreferences {
        (storageResolver as? StorageAccessManager)?.preferences ?? .default
    }

    private func readLines(fileURL: URL) throws -> [String] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .dropLastWhile { $0.isEmpty }
    }

    private func writeLines(_ lines: [String], to fileURL: URL) throws {
        let content = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"

        let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        guard let data = content.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: tempURL, options: .atomic)

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: fileURL)
        }
    }

    /// Rebuilds a task line from its parsed tokens, so edits never duplicate or drop
    /// tokens (including the hidden `date:` routing tag and the `id:`).
    private func rebuiltLine(
        for item: InboxItem,
        text: String,
        applying change: (inout InboxItem) -> Void = { _ in }
    ) throws -> String {
        // Re-parse the line on its own: inside the file a duplicated `id:` is masked,
        // but its token must still be written back unchanged.
        guard var parsed = parser.parse(lines: [item.rawLine], sourceID: "temp").first else {
            throw InboxRepositoryError.itemNotFound
        }
        change(&parsed)

        var components = [text]
        if let priority = parsed.priority { components.append("!\(priority)") }
        if let project = parsed.projectName { components.append("@\(project)") }
        for tag in parsed.tags { components.append("#\(tag)") }
        if let due = parsed.dueDate { components.append("due:\(due)") }
        for key in parsed.metadata.keys.sorted() {
            if let value = parsed.metadata[key] {
                components.append("\(key):\(value)")
            }
        }

        // Legacy lines that could not be migrated may still carry a hidden `date:` routing tag; keep it.
        let datePattern = /date:([0-9]{4}-[0-9]{2}-[0-9]{2})/
        if let dateMatch = item.rawLine.firstMatch(of: datePattern) {
            components.append("date:\(dateMatch.1)")
        }

        if let taskID = parsed.taskID {
            components.append("\(TaskIdentifier.metadataKey):\(taskID)")
        }

        let status = item.isCompleted ? "x" : " "
        return "- [\(status)] \(item.time) \(components.joined(separator: " "))"
    }

    private func normalizeToSingleLine(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func withResolvedFolder<T>(_ operation: (URL) throws -> T) throws -> T {
        let folderURL = try storageResolver.resolvedBaseURL()
        defer { storageResolver.stopAccess(for: folderURL) }
        return try operation(folderURL)
    }

    private func mappedStorageError(_ error: Error) -> Error {
        if let storageError = error as? StorageAccessError {
            switch storageError {
            case .invalidBookmark, .cannotAccessSecurityScope, .userSelectedFolderRequired:
                return InboxRepositoryError.storageUnavailable
            }
        }

        let nsError = error as NSError
        switch nsError.code {
        case NSFileWriteOutOfSpaceError:
            return InboxRepositoryError.diskFull
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return InboxRepositoryError.permissionDenied
        default:
            return error
        }
    }

}

private extension Array where Element == String {
    func dropLastWhile(_ predicate: (String) -> Bool) -> [String] {
        var result = self
        while let last = result.last, predicate(last) {
            result.removeLast()
        }
        return result
    }
}
