import Foundation

enum InboxRepositoryError: LocalizedError {
    case itemNotFound
    case nothingToUndo

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The selected item no longer exists."
        case .nothingToUndo:
            return "There is nothing to undo."
        }
    }
}

final class InboxRepository: InboxRepositorying {
    var canUndoDelete: Bool {
        lastDeleted != nil
    }

    private struct DeletedLine {
        let line: String
        let lineIndex: Int
    }

    private let storageResolver: StorageResolving
    private let fileManager: FileManager
    private let parser = InboxParser()

    private var lastDeleted: DeletedLine?

    init(storageResolver: StorageResolving, fileManager: FileManager = .default) {
        self.storageResolver = storageResolver
        self.fileManager = fileManager
    }

    func loadToday() throws -> [InboxItem] {
        try InboxStorageQueue.shared.sync {
            let fileURL = try todayFileURL()
            let lines = try readLines(fileURL: fileURL)
            return parser.parse(lines: lines, sourceID: fileURL.lastPathComponent)
        }
    }

    func reload() throws -> [InboxItem] {
        try loadToday()
    }

    func apply(_ mutation: InboxMutation) throws -> [InboxItem] {
        try InboxStorageQueue.shared.sync {
            let fileURL = try todayFileURL()
            var lines = try readLines(fileURL: fileURL)

            switch mutation {
            case .toggle(let id):
                let items = parser.parse(lines: lines, sourceID: fileURL.lastPathComponent)
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
                let items = parser.parse(lines: lines, sourceID: fileURL.lastPathComponent)
                guard let item = items.first(where: { $0.id == id }) else {
                    throw InboxRepositoryError.itemNotFound
                }

                lines.remove(at: item.lineIndex)
                lastDeleted = DeletedLine(line: item.rawLine, lineIndex: item.lineIndex)

            case .undoLastDelete:
                guard let deleted = lastDeleted else {
                    throw InboxRepositoryError.nothingToUndo
                }

                let insertIndex = min(deleted.lineIndex, lines.count)
                lines.insert(deleted.line, at: insertIndex)
                lastDeleted = nil
            }

            try writeLines(lines, to: fileURL)
            return parser.parse(lines: lines, sourceID: fileURL.lastPathComponent)
        }
    }

    private func todayFileURL() throws -> URL {
        let folderURL = try storageResolver.resolvedBaseURL()
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        return folderURL.appendingPathComponent(fileName(for: Date()))
    }

    private func fileName(for date: Date) -> String {
        Self.fileNameFormatter.string(from: date) + ".md"
    }

    private func readLines(fileURL: URL) throws -> [String] {
        defer { storageResolver.stopAccess(for: fileURL.deletingLastPathComponent()) }

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

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
