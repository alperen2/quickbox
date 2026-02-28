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
            let text = String(match.output.text)
            let id = "\(sourceID)#\(index)#\(line)"

            return InboxItem(
                id: id,
                text: text,
                time: time,
                isCompleted: isCompleted,
                lineIndex: index,
                rawLine: line
            )
        }
    }
}
