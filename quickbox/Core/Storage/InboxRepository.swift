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
                    var allItems: [InboxItem] = []
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let dateString = dateFormatter.string(from: date)
                    let dateTag = "date:\(dateString)"
                    
                    // 1. Load the default daily log file
                    let defaultFileURL = try fileURL(for: date, in: folderURL)
                    if fileManager.fileExists(atPath: defaultFileURL.path) {
                        let lines = try readLines(fileURL: defaultFileURL)
                        let items = parser.parse(lines: lines, sourceID: defaultFileURL.lastPathComponent)
                        allItems.append(contentsOf: items)
                    }
                    
                    // 2. Scan all other .md files for routed project tasks with the date tag
                    let contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                    let otherMarkdowns = contents.filter { $0.pathExtension == "md" && $0.lastPathComponent != defaultFileURL.lastPathComponent }
                    
                    for mdFileURL in otherMarkdowns {
                        let lines = try readLines(fileURL: mdFileURL)
                        // Only parse lines that actually contain the date tag to save performance
                        let matchingLines = lines.enumerated().filter { $0.element.contains(dateTag) }
                        
                        // We still need to pass the real line index from the file to the parser to allow correct edits
                        // However, InboxParser expects an array of strings, where index == lineIndex.
                        // To bypass this, we can parse all lines but only keep the ones we matched.
                        if !matchingLines.isEmpty {
                            let items = parser.parse(lines: lines, sourceID: mdFileURL.lastPathComponent)
                            let filteredItems = items.filter { item in
                                matchingLines.contains { $0.offset == item.lineIndex }
                            }
                            allItems.append(contentsOf: filteredItems)
                        }
                    }
                    
                    // 3. Filter out deferred tasks
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
                    case .toggle(let id), .delete(let id), .edit(let id, _):
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

                        // Re-parse the old line so we can inject the new text but keep the tags/due/priority intact
                        let parsedItems = parser.parse(lines: [item.rawLine], sourceID: "temp")
                        guard let parsedOld = parsedItems.first else { throw InboxRepositoryError.itemNotFound }

                        var components = [normalizedText]
                        if let priority = parsedOld.priority { components.append("!\(priority)") }
                        if let project = parsedOld.projectName { components.append("@\(project)") }
                        for tag in parsedOld.tags { components.append("#\(tag)") }
                        if let due = parsedOld.dueDate { components.append("due:\(due)") }
                        
                        // Keep the date metadata tag if it exists in the raw line (even if parser stripped it)
                        let datePattern = /date:([0-9]{4}-[0-9]{2}-[0-9]{2})/
                        if let dateMatch = item.rawLine.firstMatch(of: datePattern) {
                            components.append("date:\(dateMatch.1)")
                        }

                        let finalString = components.joined(separator: " ")
                        let status = item.isCompleted ? "x" : " "
                        lines[item.lineIndex] = "- [\(status)] \(item.time) \(finalString)"

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
                    // 1. Get items from the file we just edited
                    let persistedLines = try readLines(fileURL: fileURL)
                    let itemsThisFile = parser.parse(lines: persistedLines, sourceID: sourceID)
                    
                    // 2. Load the rest of the items for this date to reconstruct the full Inbox view
                    var allItems: [InboxItem] = []
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let dateString = dateFormatter.string(from: date)
                    let dateTag = "date:\(dateString)"
                    
                    let contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                    let allMarkdowns = contents.filter { $0.pathExtension == "md" }
                    
                    let defaultFileURL = try self.fileURL(for: date, in: folderURL)
                    
                    for mdFileURL in allMarkdowns {
                        if mdFileURL == fileURL {
                            // We just edited this one, use the fresh parse
                            if mdFileURL == defaultFileURL {
                                allItems.append(contentsOf: itemsThisFile)
                            } else {
                                // Filter by date tag if it's a project
                                let filtered = itemsThisFile.filter { $0.rawLine.contains(dateTag) }
                                allItems.append(contentsOf: filtered)
                            }
                        } else {
                            let otherLines = try readLines(fileURL: mdFileURL)
                            if mdFileURL == defaultFileURL {
                                let otherItems = parser.parse(lines: otherLines, sourceID: mdFileURL.lastPathComponent)
                                allItems.append(contentsOf: otherItems)
                            } else {
                                let matchingLines = otherLines.enumerated().filter { $0.element.contains(dateTag) }
                                if !matchingLines.isEmpty {
                                    let otherItems = parser.parse(lines: otherLines, sourceID: mdFileURL.lastPathComponent)
                                    let filteredItems = otherItems.filter { item in
                                        matchingLines.contains { $0.offset == item.lineIndex }
                                    }
                                    allItems.append(contentsOf: filteredItems)
                                }
                            }
                        }
                    }

                    return allItems.sorted { $0.time < $1.time }
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
