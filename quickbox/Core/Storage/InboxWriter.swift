import Foundation
import QuickboxCore

protocol InboxWriting {
    func appendEntry(_ text: String, now: Date) throws
}

enum InboxWriterError: LocalizedError, Equatable {
    case emptyEntry
    case permissionDenied
    case diskFull
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyEntry:
            return "Please type something before saving."
        case .permissionDenied:
            return "quickbox cannot write to the storage folder. Check folder permissions in Settings."
        case .diskFull:
            return "Your disk appears to be full. Free some space and try again."
        case .storageUnavailable:
            return "Storage is currently unavailable. Please reselect the folder in Settings."
        }
    }
}

final class InboxWriter: InboxWriting {
    private let storageResolver: StorageResolving
    private let fileManager: FileManager
    private let makeTaskID: () -> String

    init(
        storageResolver: StorageResolving,
        fileManager: FileManager = .default,
        makeTaskID: @escaping () -> String = TaskIdentifier.generate
    ) {
        self.storageResolver = storageResolver
        self.fileManager = fileManager
        self.makeTaskID = makeTaskID
    }

    func appendEntry(_ text: String, now: Date = Date()) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InboxWriterError.emptyEntry
        }
        
        // Parse the text to extract tokens
        let parser = InboxParser()
        let parsedItems = parser.parse(lines: ["- [ ] 00:00 " + trimmed], sourceID: "temp")
        guard var item = parsedItems.first else { throw InboxWriterError.emptyEntry }
        if item.taskID == nil {
            item.taskID = makeTaskID()
        }
        
        let preferences = currentPreferences()
        
        do {
            try InboxStorageQueue.shared.sync {
                let folderURL = try storageResolver.resolvedBaseURL()
                defer { storageResolver.stopAccess(for: folderURL) }

                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)

                let targetDate: Date
                if let dueStr = item.dueDate, let resolvedDue = DueDateResolver().resolve(dueDateString: dueStr, from: now) {
                    targetDate = resolvedDue
                } else {
                    targetDate = now
                }

                // Project entries go to `<Project>/<date>.md`, others to `<date>.md`
                let layout = StorageLayout(preferences: preferences, fileManager: fileManager)
                let relativePath = layout.relativePath(for: targetDate, project: item.projectName)
                let fileURL = folderURL.appendingPathComponent(relativePath)
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

                let line = formattedLine(for: item, captureDate: now)
                let entryText = normalizedEntry(for: fileURL, line: line)
                let data = Data(entryText.utf8)

                if !fileManager.fileExists(atPath: fileURL.path) {
                    try data.write(to: fileURL, options: .atomic)
                } else {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                }

                let persistedData = try Data(contentsOf: fileURL)
                guard !persistedData.isEmpty else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        } catch {
            throw mappedStorageError(error)
        }
    }

    func fileName(for date: Date) -> String {
        FormatSettings.fileName(for: date, preferences: currentPreferences())
    }

    // Reconstructs the line ensuring correct formatting
    func formattedLine(for item: InboxItem, captureDate: Date) -> String {
        let oneLine = item.text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            
        var components = [oneLine]
        
        if let priority = item.priority {
            components.append("!\(priority)")
        }
        if let project = item.projectName {
            components.append("@\(project)")
        }
        for tag in item.tags {
            components.append("#\(tag)")
        }
        if let due = item.dueDate {
            // Re-resolve the date to format it consistently based on user settings
            if let resolvedDue = DueDateResolver().resolve(dueDateString: due, from: captureDate) {
                let formattedDue = FormatSettings.fileName(for: resolvedDue, preferences: currentPreferences()).replacingOccurrences(of: ".md", with: "")
                components.append("due:\(formattedDue)")
            } else {
                components.append("due:\(due)") // fallback to original if unresolvable
            }
        }
        
        // Append all dynamic key:value metadata
        for key in item.metadata.keys.sorted() {
             if let value = item.metadata[key] {
                 components.append("\(key):\(value)")
             }
        }

        if let taskID = item.taskID {
            components.append("\(TaskIdentifier.metadataKey):\(taskID)")
        }

        let finalString = components.joined(separator: " ")
        let time = FormatSettings.timeText(for: captureDate, preferences: currentPreferences())
        return "- [ ] \(time) \(finalString)"
    }

    private func currentPreferences() -> AppPreferences {
        (storageResolver as? StorageAccessManager)?.preferences ?? .default
    }

    private func normalizedEntry(for fileURL: URL, line: String) -> String {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              !data.isEmpty
        else {
            return line + "\n"
        }

        if data.last == 0x0A {
            return line + "\n"
        }

        return "\n" + line + "\n"
    }

    private func mappedStorageError(_ error: Error) -> Error {
        if let storageError = error as? StorageAccessError {
            switch storageError {
            case .invalidBookmark, .cannotAccessSecurityScope, .userSelectedFolderRequired:
                return InboxWriterError.storageUnavailable
            }
        }

        let nsError = error as NSError
        switch nsError.code {
        case NSFileWriteOutOfSpaceError:
            return InboxWriterError.diskFull
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return InboxWriterError.permissionDenied
        default:
            return error
        }
    }

}
