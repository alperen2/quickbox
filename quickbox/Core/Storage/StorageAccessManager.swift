import Foundation
import OSLog

protocol StorageResolving {
    func resolvedBaseURL() throws -> URL
    func stopAccess(for url: URL)
}

enum StorageAccessError: LocalizedError, Equatable {
    case invalidBookmark
    case cannotAccessSecurityScope
    case userSelectedFolderRequired

    var errorDescription: String? {
        switch self {
        case .invalidBookmark:
            return "The selected folder bookmark is invalid. Please reselect a folder in Settings."
        case .cannotAccessSecurityScope:
            return "The selected folder cannot be accessed. Please reselect a folder in Settings."
        case .userSelectedFolderRequired:
            return "Choose a storage folder before saving."
        }
    }
}

final class StorageAccessManager: StorageResolving {
    var preferences: AppPreferences
    private let logger = Logger(subsystem: "quickbox", category: "storage")

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    var needsUserSelectedFolder: Bool {
        requiresSecurityScopedStorage && preferences.storageBookmarkData == nil
    }

    func resolvedBaseURL() throws -> URL {
        if let bookmarkData = preferences.storageBookmarkData {
            var isStale = false
            let url: URL
            do {
                url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } catch {
                logger.error("Bookmark resolution failed: \(error.localizedDescription, privacy: .public) (\(String(describing: error), privacy: .public))")
                throw StorageAccessError.invalidBookmark
            }

            if isStale {
                logger.notice("Storage bookmark is stale for \(url.path, privacy: .public)")
            }

            guard url.startAccessingSecurityScopedResource() else {
                logger.error("startAccessingSecurityScopedResource returned false for \(url.path, privacy: .public)")
                throw StorageAccessError.cannotAccessSecurityScope
            }

            return url
        }

        if requiresSecurityScopedStorage {
            throw StorageAccessError.userSelectedFolderRequired
        }

        let expandedPath = (preferences.fallbackStoragePath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
    }

    func stopAccess(for url: URL) {
        guard preferences.storageBookmarkData != nil else {
            return
        }

        url.stopAccessingSecurityScopedResource()
    }

    func makeBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private var requiresSecurityScopedStorage: Bool {
        Bundle.main.bundleIdentifier == "alperen.quickbox.appstore"
    }
}
