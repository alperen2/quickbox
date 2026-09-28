import Foundation

/// Single source of truth for where entries live inside the storage folder.
///
/// - Inbox entries:   `<base>/<prefix><date>.md`
/// - Project entries: `<base>/<Project>/<prefix><date>.md`
///
/// Older versions stored project entries in a flat `<base>/<Project>.md` file;
/// `LegacyProjectMigrator` moves those into this layout.
struct StorageLayout {
    private let preferences: AppPreferences
    private let fileManager: FileManager

    init(preferences: AppPreferences, fileManager: FileManager = .default) {
        self.preferences = preferences
        self.fileManager = fileManager
    }

    func dailyFileName(for date: Date) -> String {
        FormatSettings.fileName(for: date, preferences: preferences)
    }

    /// Path relative to the storage folder. Also used as the item `sourceID`.
    func relativePath(for date: Date, project: String?) -> String {
        let fileName = dailyFileName(for: date)
        guard let project else { return fileName }
        return "\(project)/\(fileName)"
    }

    func projectDirectories(in baseURL: URL) throws -> [URL] {
        try Self.projectDirectories(in: baseURL, fileManager: fileManager)
    }

    /// Nonisolated so background scans (e.g. the autocomplete index) can list projects off the main actor.
    nonisolated static func projectDirectories(in baseURL: URL, fileManager: FileManager = .default) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
