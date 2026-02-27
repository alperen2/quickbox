import Foundation

protocol StorageResolving {
    func resolvedBaseURL() throws -> URL
    func stopAccess(for url: URL)
}

enum StorageAccessError: LocalizedError, Equatable {
    case invalidBookmark
    case cannotAccessSecurityScope

    var errorDescription: String? {
        switch self {
        case .invalidBookmark:
            return "The selected folder bookmark is invalid. Please reselect a folder in Settings."
        case .cannotAccessSecurityScope:
            return "The selected folder cannot be accessed. Please reselect a folder in Settings."
        }
    }
}

final class StorageAccessManager: StorageResolving {
    var preferences: AppPreferences

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    func resolvedBaseURL() throws -> URL {
        if let bookmarkData = preferences.storageBookmarkData {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                guard url.startAccessingSecurityScopedResource() else {
                    throw StorageAccessError.cannotAccessSecurityScope
                }

                return url
            } catch {
                throw StorageAccessError.invalidBookmark
            }
        }

        return URL(fileURLWithPath: preferences.fallbackStoragePath, isDirectory: true)
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
}
