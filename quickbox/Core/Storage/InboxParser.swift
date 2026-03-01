import Foundation

struct InboxParser {
    private static let taskPattern = /^- \[(?<done>[ xX])\] (?<time>\d{2}:\d{2}) (?<text>.+)$/

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
            // Generic key-value pattern: word:word (no spaces). 
            // Negative lookbehind `(?<!...)` isn't fully supported in Swift regex literals natively matching `http:` 
            // so we handle it manually by filtering out `http:` or `https:`.
            let kvPattern = /([a-zA-Z0-9_\-]+):([a-zA-Z0-9_\-]+)/

            for tagMatch in text.matches(of: tagPattern) {
                tags.append(String(tagMatch.1))
            }
            
            if let priorityMatch = text.firstMatch(of: priorityPattern) {
                priority = Int(priorityMatch.1)
            }
            
            if let projectMatch = text.firstMatch(of: projectPattern) {
                projectName = String(projectMatch.1)
            }
            
            // Extract all key:value pairs
            for kvMatch in text.matches(of: kvPattern) {
                let key = String(kvMatch.1)
                let val = String(kvMatch.2)
                
                // Ignore URLs
                if key.lowercased() == "http" || key.lowercased() == "https" { continue }
                
                if key.lowercased() == "due" {
                    dueDate = val
                } else if key.lowercased() != "date" { // Hide internal `date:` routing tags
                    metadata[key] = val
                }
            }
            
            text = text.replacing(tagPattern, with: "")
            text = text.replacing(priorityPattern, with: "")
            text = text.replacing(projectPattern, with: "")
            
            // Remove key:value pairs from text (ensuring we don't break URLs)
            for kvMatch in text.matches(of: kvPattern) {
                let key = String(kvMatch.1)
                if key.lowercased() != "http" && key.lowercased() != "https" {
                    text = text.replacing(kvMatch.output.0, with: "")
                }
            }
            
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
}
