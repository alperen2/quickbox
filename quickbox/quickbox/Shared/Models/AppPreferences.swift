import Foundation

enum AfterSaveMode: String, Codable, CaseIterable, Identifiable {
    case close
    case keepOpen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .close:
            return "Close window"
        case .keepOpen:
            return "Keep window open"
        }
    }
}

struct AppPreferences: Codable {
    var shortcutKey: String
    var afterSaveMode: AfterSaveMode
    var storageBookmarkData: Data?
    var fallbackStoragePath: String
    var launchAtLogin: Bool

    static let defaultShortcut = "control+option+space"
    static let defaultFolderName = "ADHD-Inbox"

    static var `default`: AppPreferences {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(defaultFolderName, isDirectory: true)
            .path ?? ("~/Documents/" + defaultFolderName)

        return AppPreferences(
            shortcutKey: defaultShortcut,
            afterSaveMode: .close,
            storageBookmarkData: nil,
            fallbackStoragePath: documentsPath,
            launchAtLogin: false
        )
    }
}
