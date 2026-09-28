import Foundation
import Testing
@testable import QuickboxCore

/// Runs the language-neutral golden cases in `fixtures/due-dates.json`, shared with the cloud resolver.
struct DueDateFixtureTests {

    @Test(arguments: try loadCases())
    func resolverMatchesGoldenCase(_ fixture: DueDateFixture) throws {
        let calendar = Calendar.current
        let reference = try #require(Self.dateFormatter.date(from: fixture.reference))
        // Mid-day reference keeps the result independent of DST transitions.
        let referenceNoon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: reference))

        let resolved = DueDateResolver().resolve(dueDateString: fixture.input, from: referenceNoon)

        #expect(resolved.map(Self.dateFormatter.string(from:)) == fixture.expected)
    }

    static func loadCases() throws -> [DueDateFixture] {
        let data = try Data(contentsOf: FixtureLocation.url(named: "due-dates.json"))
        let file = try JSONDecoder().decode(DueDateFixtureFile.self, from: data)
        return file.groups.flatMap { group in
            group.cases.map { DueDateFixture(reference: group.reference, input: $0.input, expected: $0.expected) }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct DueDateFixtureFile: Decodable {
    struct Group: Decodable {
        let reference: String
        let cases: [Case]
    }

    struct Case: Decodable {
        let input: String
        let expected: String?
    }

    let groups: [Group]
}

struct DueDateFixture: Sendable, CustomTestStringConvertible {
    let reference: String
    let input: String
    let expected: String?

    var testDescription: String { "\(reference) + \"\(input)\"" }
}
