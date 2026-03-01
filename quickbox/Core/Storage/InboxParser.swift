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

            let tagPattern = /#([a-zA-Z0-9_\-]+)/
            let duePattern = /due:([a-zA-Z0-9_\-]+)/
            let priorityPattern = /!([1-3])/
            let projectPattern = /@([a-zA-Z0-9_\-]+)/
            let datePattern = /date:([0-9]{4}-[0-9]{2}-[0-9]{2})/

            for tagMatch in text.matches(of: tagPattern) {
                tags.append(String(tagMatch.1))
            }
            
            if let dueMatch = text.firstMatch(of: duePattern) {
                dueDate = String(dueMatch.1)
            }
            
            if let priorityMatch = text.firstMatch(of: priorityPattern) {
                priority = Int(priorityMatch.1)
            }
            
            if let projectMatch = text.firstMatch(of: projectPattern) {
                projectName = String(projectMatch.1)
            }
            // date metadata in the file just helps routing, but we can also hide it from UI text
            
            text = text.replacing(tagPattern, with: "")
            text = text.replacing(duePattern, with: "")
            text = text.replacing(priorityPattern, with: "")
            text = text.replacing(projectPattern, with: "")
            text = text.replacing(datePattern, with: "")
            text = text.trimmingCharacters(in: .whitespaces)

            return InboxItem(
                id: id,
                text: text,
                tags: tags,
                dueDate: dueDate,
                priority: priority,
                projectName: projectName,
                time: time,
                isCompleted: isCompleted,
                lineIndex: index,
                rawLine: line
            )
        }
    }
}
