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
    var fileDateFormat: String
    var timeFormat: String
    var fileNamePrefix: String
    var crashReportingEnabled: Bool

    static let defaultShortcut = "command+shift+space"
    static let defaultFileDateFormat = "yyyy-MM-dd"
    static let defaultTimeFormat = "HH:mm"
    static let legacyFallbackStoragePath = "~/Documents/Quickbox"
    static let newFallbackStoragePath = "~/Documents/Pigeon"

    /// Preferences are saved only after a change, so users who never touched Settings read this
    /// default on every launch: keep them on the folder that already holds their tasks.
    static func defaultFallbackStoragePath(
        folderExists: (String) -> Bool = { FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath) }
    ) -> String {
        folderExists(legacyFallbackStoragePath) ? legacyFallbackStoragePath : newFallbackStoragePath
    }

    static var `default`: AppPreferences {
        return AppPreferences(
            shortcutKey: defaultShortcut,
            afterSaveMode: .close,
            storageBookmarkData: nil,
            fallbackStoragePath: defaultFallbackStoragePath(),
            launchAtLogin: false,
            fileDateFormat: defaultFileDateFormat,
            timeFormat: defaultTimeFormat,
            fileNamePrefix: "",
            crashReportingEnabled: false
        )
    }

    private enum CodingKeys: String, CodingKey {
        case shortcutKey
        case afterSaveMode
        case storageBookmarkData
        case fallbackStoragePath
        case launchAtLogin
        case fileDateFormat
        case timeFormat
        case fileNamePrefix
        case crashReportingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppPreferences.default
        shortcutKey = try container.decodeIfPresent(String.self, forKey: .shortcutKey) ?? defaults.shortcutKey
        afterSaveMode = try container.decodeIfPresent(AfterSaveMode.self, forKey: .afterSaveMode) ?? defaults.afterSaveMode
        storageBookmarkData = try container.decodeIfPresent(Data.self, forKey: .storageBookmarkData)
        fallbackStoragePath = try container.decodeIfPresent(String.self, forKey: .fallbackStoragePath) ?? defaults.fallbackStoragePath
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        fileDateFormat = try container.decodeIfPresent(String.self, forKey: .fileDateFormat) ?? defaults.fileDateFormat
        timeFormat = try container.decodeIfPresent(String.self, forKey: .timeFormat) ?? defaults.timeFormat
        fileNamePrefix = try container.decodeIfPresent(String.self, forKey: .fileNamePrefix) ?? defaults.fileNamePrefix
        crashReportingEnabled = try container.decodeIfPresent(Bool.self, forKey: .crashReportingEnabled) ?? defaults.crashReportingEnabled
    }

    init(
        shortcutKey: String,
        afterSaveMode: AfterSaveMode,
        storageBookmarkData: Data?,
        fallbackStoragePath: String,
        launchAtLogin: Bool,
        fileDateFormat: String,
        timeFormat: String,
        fileNamePrefix: String,
        crashReportingEnabled: Bool
    ) {
        self.shortcutKey = shortcutKey
        self.afterSaveMode = afterSaveMode
        self.storageBookmarkData = storageBookmarkData
        self.fallbackStoragePath = fallbackStoragePath
        self.launchAtLogin = launchAtLogin
        self.fileDateFormat = fileDateFormat
        self.timeFormat = timeFormat
        self.fileNamePrefix = fileNamePrefix
        self.crashReportingEnabled = crashReportingEnabled
    }
}
