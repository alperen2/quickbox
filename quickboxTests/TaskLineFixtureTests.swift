import Foundation
import Testing
@testable import quickbox

/// Runs the language-neutral golden cases in `fixtures/task-lines.json`.
/// Any other parser implementation must pass the same file, which keeps them from drifting apart.
@MainActor
struct TaskLineFixtureTests {

    @Test(arguments: try loadCases())
    func parserMatchesGoldenCase(_ fixture: TaskLineFixture) {
        let items = InboxParser().parse(lines: fixture.lines, sourceID: "fixture.md")
        let actual = items.map(ExpectedItem.init)

        #expect(actual == fixture.expected, "\(fixture.name)")
    }

    nonisolated static func loadCases() throws -> [TaskLineFixture] {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/task-lines.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(FixtureFile.self, from: data).cases
    }
}

private struct FixtureFile: Decodable {
    let cases: [TaskLineFixture]
}

struct TaskLineFixture: Decodable, Sendable, CustomTestStringConvertible {
    let name: String
    let lines: [String]
    let expected: [ExpectedItem]

    var testDescription: String { name }
}

struct ExpectedItem: Decodable, Equatable, Sendable {
    let lineIndex: Int
    let completed: Bool
    let time: String
    let text: String
    let tags: [String]
    let priority: Int?
    let project: String?
    let due: String?
    let metadata: [String: String]
    let taskID: String?
}

extension ExpectedItem {
    @MainActor init(_ item: InboxItem) {
        self.init(
            lineIndex: item.lineIndex,
            completed: item.isCompleted,
            time: item.time,
            text: item.text,
            tags: item.tags,
            priority: item.priority,
            project: item.projectName,
            due: item.dueDate,
            metadata: item.metadata,
            taskID: item.taskID
        )
    }
}
