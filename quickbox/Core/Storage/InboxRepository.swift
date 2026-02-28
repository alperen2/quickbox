import Foundation

enum InboxRepositoryError: LocalizedError, Equatable {
    case itemNotFound
    case nothingToUndo
    case emptyEditedText
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
        case .permissionDenied:
            return "quickbox cannot write to the storage folder. Check folder permissions in Settings."
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

    private struct DeletedLine {
        let line: String
        let lineIndex: Int
        let sourceID: String
    }

    private let storageResolver: StorageResolving
    private let fileManager: FileManager
    private let parser = InboxParser()

    private var lastDeleted: DeletedLine?

    init(storageResolver: StorageResolving, fileManager: FileManager = .default) {
        self.storageResolver = storageResolver
        self.fileManager = fileManager
    }

    func load(on date: Date) throws -> [InboxItem] {
        do {
            return try InboxStorageQueue.shared.sync {
                try withResolvedFolder { folderURL in
                    let fileURL = try fileURL(for: date, in: folderURL)
                    let lines = try readLines(fileURL: fileURL)
                    return parser.parse(lines: lines, sourceID: fileURL.lastPathComponent)
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
                    let fileURL = try fileURL(for: date, in: folderURL)
                    var lines = try readLines(fileURL: fileURL)
                    let sourceID = fileURL.lastPathComponent

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

                        let status = item.isCompleted ? "x" : " "
                        lines[item.lineIndex] = "- [\(status)] \(item.time) \(normalizedText)"

                    case .undoLastDelete:
                        guard let deleted = lastDeleted, deleted.sourceID == sourceID else {
                            throw InboxRepositoryError.nothingToUndo
                        }

                        let insertIndex = min(deleted.lineIndex, lines.count)
                        lines.insert(deleted.line, at: insertIndex)
                        lastDeleted = nil
                    }

                    try writeLines(lines, to: fileURL)
                    let persistedLines = try readLines(fileURL: fileURL)
                    return parser.parse(lines: persistedLines, sourceID: sourceID)
                }
            }
        } catch {
            throw mappedStorageError(error)
        }
    }

    func apply(_ mutation: InboxMutation) throws -> [InboxItem] {
        try apply(mutation, on: Date())
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
            case .invalidBookmark, .cannotAccessSecurityScope:
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
