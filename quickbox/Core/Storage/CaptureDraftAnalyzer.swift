import Foundation

struct DraftTokenInsight: Equatable, Sendable {
    let key: String
    let rawValue: String
    let preview: String
    let isResolved: Bool
}

struct CaptureDraftAnalyzer {
    private static let dateMetadataKeys: Set<String> = ["due", "defer", "start"]
    private static let durationMetadataKeys: Set<String> = ["dur", "time", "duration", "remind", "alarm"]
    private static let metadataKeyPattern = /^[a-zA-Z0-9_\-]+$/
    private static let nextMetadataPattern = /^[a-zA-Z0-9_\-]+:/
    private static let compactRelativeDatePattern = /^in\d+(day|days|d|week|weeks|w|month|months|m)$/
    private static let numericPattern = /^\d+$/
    private static let datePhraseTokens: Set<String> = [
        "today", "tdy",
        "tomorrow", "tmr",
        "next",
        "in",
        "week", "weekend",
        "weeks",
        "end", "of",
        "day", "days",
        "month", "months",
        "year",
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"
    ]

    private let dueResolver = DueDateResolver()

    func analyze(_ text: String, now: Date = Date()) -> [DraftTokenInsight] {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            return []
        }

        var insights: [DraftTokenInsight] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            guard let colonIndex = token.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let rawKey = String(token[..<colonIndex]).lowercased()
            let inlineValue = String(token[token.index(after: colonIndex)...])
            guard isValidMetadataKey(rawKey), rawKey != "http", rawKey != "https" else {
                index += 1
                continue
            }

            if Self.dateMetadataKeys.contains(rawKey) {
                var phraseTokens: [String] = []
                if !inlineValue.isEmpty {
                    phraseTokens.append(inlineValue)
                }

                var lookahead = index + 1
                while lookahead < tokens.count && shouldContinueDatePhrase(with: tokens[lookahead]) {
                    phraseTokens.append(tokens[lookahead])
                    lookahead += 1
                }

                let phrase = phraseTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !phrase.isEmpty {
                    if let resolvedDate = dueResolver.resolve(dueDateString: phrase, from: now) {
                        insights.append(
                            DraftTokenInsight(
                                key: rawKey,
                                rawValue: phrase,
                                preview: datePreview(for: resolvedDate),
                                isResolved: true
                            )
                        )
                    } else {
                        insights.append(
                            DraftTokenInsight(
                                key: rawKey,
                                rawValue: phrase,
                                preview: "Unresolved date",
                                isResolved: false
                            )
                        )
                    }
                    index = lookahead
                    continue
                }
            } else if Self.durationMetadataKeys.contains(rawKey), !inlineValue.isEmpty {
                let normalized = durationPreview(for: inlineValue, now: now)
                insights.append(
                    DraftTokenInsight(
                        key: rawKey,
                        rawValue: inlineValue,
                        preview: normalized.preview,
                        isResolved: normalized.isResolved
                    )
                )
            }

            index += 1
        }

        return insights
    }

    private func datePreview(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM, EEE"
        return formatter.string(from: date)
    }

    private func durationPreview(for value: String, now: Date) -> (preview: String, isResolved: Bool) {
        guard let minutes = parseDurationToMinutes(value), minutes > 0 else {
            return ("Unsupported duration", false)
        }

        guard let target = Calendar.current.date(byAdding: .minute, value: minutes, to: now) else {
            return ("Unsupported duration", false)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return ("+\(minutes)m -> \(formatter.string(from: target))", true)
    }

    private func parseDurationToMinutes(_ value: String) -> Int? {
        guard let unit = value.last, let amount = Int(value.dropLast()), amount > 0 else {
            return nil
        }

        switch unit {
        case "m": return amount
        case "h": return amount * 60
        case "d": return amount * 24 * 60
        default: return nil
        }
    }

    private func isValidMetadataKey(_ key: String) -> Bool {
        key.wholeMatch(of: Self.metadataKeyPattern) != nil
    }

    private func shouldContinueDatePhrase(with token: String) -> Bool {
        let normalized = token.lowercased()
        if normalized.hasPrefix("#") || normalized.hasPrefix("@") || normalized.hasPrefix("!") {
            return false
        }
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return false
        }
        if normalized.firstMatch(of: Self.nextMetadataPattern) != nil {
            return false
        }
        if Self.datePhraseTokens.contains(normalized) {
            return true
        }
        if normalized.wholeMatch(of: Self.numericPattern) != nil {
            return true
        }
        if normalized.wholeMatch(of: Self.compactRelativeDatePattern) != nil {
            return true
        }
        return false
    }
}
