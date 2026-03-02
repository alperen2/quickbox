import Foundation

struct InboxParser {
    private static let taskPattern = /^- \[(?<done>[ xX])\] (?<time>\d{2}:\d{2}) (?<text>.+)$/
    private static let dateMetadataKeys: Set<String> = ["due", "defer", "start"]
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

    func parse(lines: [String], sourceID: String) -> [InboxItem] {
        lines.enumerated().compactMap { index, line in
            guard let match = line.firstMatch(of: Self.taskPattern) else {
                return nil
            }

            let isCompleted = match.output.done != " "
            let time = String(match.output.time)
            var text = String(match.output.text)
            let id = "\(sourceID)#\(index)#\(line)"
            
            var tags: [String] = []
            var dueDate: String? = nil
            var priority: Int? = nil
            var projectName: String? = nil
            var metadata: [String: String] = [:]

            let tagPattern = /#([a-zA-Z0-9_\-]+)/
            let priorityPattern = /!([1-3])/
            let projectPattern = /@([a-zA-Z0-9_\-]+)/

            for tagMatch in text.matches(of: tagPattern) {
                tags.append(String(tagMatch.1))
            }
            
            if let priorityMatch = text.firstMatch(of: priorityPattern) {
                priority = Int(priorityMatch.1)
            }
            
            if let projectMatch = text.firstMatch(of: projectPattern) {
                projectName = String(projectMatch.1)
            }

            let metadataExtraction = extractMetadataTokens(from: text)
            for (key, value) in metadataExtraction.values {
                if key == "due" {
                    dueDate = value
                } else if key != "date" {
                    // Hide internal `date:` routing tags from UI metadata.
                    metadata[key] = value
                }
            }

            text = metadataExtraction.remainingText
            text = text.replacing(tagPattern, with: "")
            text = text.replacing(priorityPattern, with: "")
            text = text.replacing(projectPattern, with: "")
            text = text.trimmingCharacters(in: .whitespaces)

            return InboxItem(
                id: id,
                text: text,
                tags: tags,
                dueDate: dueDate,
                priority: priority,
                projectName: projectName,
                metadata: metadata,
                time: time,
                isCompleted: isCompleted,
                lineIndex: index,
                rawLine: line
            )
        }
    }

    private func extractMetadataTokens(from text: String) -> (values: [String: String], remainingText: String) {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            return ([:], text)
        }

        var values: [String: String] = [:]
        var consumedIndices = Set<Int>()
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            guard let colonIndex = token.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let rawKey = String(token[..<colonIndex])
            let key = rawKey.lowercased()
            guard isValidMetadataKey(key) else {
                index += 1
                continue
            }
            if key == "http" || key == "https" {
                index += 1
                continue
            }

            let inlineValue = String(token[token.index(after: colonIndex)...])

            if Self.dateMetadataKeys.contains(key) {
                var phraseTokens: [String] = []
                if !inlineValue.isEmpty {
                    phraseTokens.append(inlineValue)
                }

                var lookahead = index + 1
                while lookahead < tokens.count && shouldContinueDatePhrase(with: tokens[lookahead]) {
                    phraseTokens.append(tokens[lookahead])
                    lookahead += 1
                }

                let phrase = phraseTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !phrase.isEmpty {
                    values[key] = phrase
                    for consumed in index..<lookahead {
                        consumedIndices.insert(consumed)
                    }
                    index = lookahead
                    continue
                }
            } else if !inlineValue.isEmpty {
                values[key] = inlineValue
                consumedIndices.insert(index)
            }

            index += 1
        }

        let remaining = tokens.enumerated()
            .compactMap { consumedIndices.contains($0.offset) ? nil : $0.element }
            .joined(separator: " ")
        return (values, remaining)
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
