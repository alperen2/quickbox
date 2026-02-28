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
    var autoUpdateEnabled: Bool
    var betaChannelEnabled: Bool

    static let defaultShortcut = "command+shift+space"
    static let defaultFolderName = "Quickbox"
    static let defaultFileDateFormat = "yyyy-MM-dd"
    static let defaultTimeFormat = "HH:mm"

    static var `default`: AppPreferences {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(defaultFolderName, isDirectory: true)
            .path ?? ("~/Documents/" + defaultFolderName)

        return AppPreferences(
            shortcutKey: defaultShortcut,
            afterSaveMode: .close,
            storageBookmarkData: nil,
            fallbackStoragePath: documentsPath,
            launchAtLogin: false,
            fileDateFormat: defaultFileDateFormat,
            timeFormat: defaultTimeFormat,
            fileNamePrefix: "",
            crashReportingEnabled: false,
            autoUpdateEnabled: true,
            betaChannelEnabled: true
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
        case autoUpdateEnabled
        case betaChannelEnabled
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
        autoUpdateEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateEnabled) ?? defaults.autoUpdateEnabled
        betaChannelEnabled = try container.decodeIfPresent(Bool.self, forKey: .betaChannelEnabled) ?? defaults.betaChannelEnabled
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
        crashReportingEnabled: Bool,
        autoUpdateEnabled: Bool,
        betaChannelEnabled: Bool
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
        self.autoUpdateEnabled = autoUpdateEnabled
        self.betaChannelEnabled = betaChannelEnabled
    }
}
