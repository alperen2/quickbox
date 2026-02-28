import Foundation

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

    init(storageResolver: StorageResolving, fileManager: FileManager = .default) {
        self.storageResolver = storageResolver
        self.fileManager = fileManager
    }

    func appendEntry(_ text: String, now: Date = Date()) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InboxWriterError.emptyEntry
        }

        let preferences = currentPreferences()
        let line = formattedLine(for: trimmed, at: now)
        do {
            try InboxStorageQueue.shared.sync {
                let folderURL = try storageResolver.resolvedBaseURL()
                defer { storageResolver.stopAccess(for: folderURL) }

                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)

                let fileURL = folderURL.appendingPathComponent(FormatSettings.fileName(for: now, preferences: preferences))
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

    func formattedLine(for text: String, at date: Date) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let time = FormatSettings.timeText(for: date, preferences: currentPreferences())
        return "- [ ] \(time) \(oneLine)"
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
            case .invalidBookmark, .cannotAccessSecurityScope:
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
