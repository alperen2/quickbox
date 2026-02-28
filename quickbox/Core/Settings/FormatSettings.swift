import Foundation

enum DateFormatPreset: String, CaseIterable, Identifiable {
    case isoDashed
    case dayMonthYear
    case compact
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isoDashed:
            return "yyyy-MM-dd"
        case .dayMonthYear:
            return "dd-MM-yyyy"
        case .compact:
            return "yyyyMMdd"
        case .custom:
            return "Custom"
        }
    }

    var formatString: String? {
        switch self {
        case .isoDashed:
            return "yyyy-MM-dd"
        case .dayMonthYear:
            return "dd-MM-yyyy"
        case .compact:
            return "yyyyMMdd"
        case .custom:
            return nil
        }
    }

    static func preset(for format: String) -> DateFormatPreset {
        switch format {
        case "yyyy-MM-dd":
            return .isoDashed
        case "dd-MM-yyyy":
            return .dayMonthYear
        case "yyyyMMdd":
            return .compact
        default:
            return .custom
        }
    }
}

enum TimeFormatPreset: String, CaseIterable, Identifiable {
    case twentyFourHour
    case twelveHour
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twentyFourHour:
            return "24h (HH:mm)"
        case .twelveHour:
            return "12h (hh:mm a)"
        case .custom:
            return "Custom"
        }
    }

    var formatString: String? {
        switch self {
        case .twentyFourHour:
            return "HH:mm"
        case .twelveHour:
            return "hh:mm a"
        case .custom:
            return nil
        }
    }

    static func preset(for format: String) -> TimeFormatPreset {
        switch format {
        case "HH:mm":
            return .twentyFourHour
        case "hh:mm a":
            return .twelveHour
        default:
            return .custom
        }
    }
}

enum FormatSettings {
    static func isValidDateFormat(_ format: String) -> Bool {
        isValid(format: format)
    }

    static func isValidTimeFormat(_ format: String) -> Bool {
        isValid(format: format)
    }

    static func sanitizePrefix(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let invalid = CharacterSet(charactersIn: "/\\:\n\r\t")
        let cleanedScalars = trimmed.unicodeScalars.map { invalid.contains($0) ? "-" : String($0) }
        let sanitized = cleanedScalars.joined()
        return String(sanitized.prefix(32))
    }

    static func resolvedDateFormat(from preferences: AppPreferences) -> String {
        if isValidDateFormat(preferences.fileDateFormat) {
            return preferences.fileDateFormat
        }
        return AppPreferences.defaultFileDateFormat
    }

    static func resolvedTimeFormat(from preferences: AppPreferences) -> String {
        if isValidTimeFormat(preferences.timeFormat) {
            return preferences.timeFormat
        }
        return AppPreferences.defaultTimeFormat
    }

    static func fileName(for date: Date, preferences: AppPreferences) -> String {
        let dateText = formattedDate(date, format: resolvedDateFormat(from: preferences))
        let prefix = sanitizePrefix(preferences.fileNamePrefix)
        return "\(prefix)\(dateText).md"
    }

    static func timeText(for date: Date, preferences: AppPreferences) -> String {
        formattedDate(date, format: resolvedTimeFormat(from: preferences))
    }

    static func dateLabel(for date: Date, preferences: AppPreferences) -> String {
        formattedDate(date, format: resolvedDateFormat(from: preferences))
    }

    private static func formattedDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func isValid(format: String) -> Bool {
        let trimmed = format.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = trimmed

        let rendered = formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000))
        return !rendered.isEmpty && rendered != trimmed
    }
}
