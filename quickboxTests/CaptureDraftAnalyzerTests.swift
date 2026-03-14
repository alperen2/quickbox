import Foundation
import Testing
@testable import quickbox

struct CaptureDraftAnalyzerTests {
    private let analyzer = CaptureDraftAnalyzer()

    @Test
    func resolvesNaturalDatePreview() {
        let now = makeDate(year: 2026, month: 3, day: 2, hour: 9, minute: 30)
        let insights = analyzer.analyze("Prepare brief due:next friday", now: now)

        guard let dueInsight = insights.first(where: { $0.key == "due" }) else {
            #expect(Bool(false), "Expected due insight")
            return
        }

        guard let expectedDate = DueDateResolver().resolve(dueDateString: "next friday", from: now) else {
            #expect(Bool(false), "Expected next friday to resolve")
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM, EEE"

        #expect(dueInsight.isResolved)
        #expect(dueInsight.rawValue == "next friday")
        #expect(dueInsight.preview == formatter.string(from: expectedDate))
    }

    @Test
    func marksInvalidDateAsUnresolved() {
        let now = makeDate(year: 2026, month: 3, day: 2, hour: 9, minute: 30)
        let insights = analyzer.analyze("Call vendor due:not-a-date", now: now)

        guard let dueInsight = insights.first(where: { $0.key == "due" }) else {
            #expect(Bool(false), "Expected due insight")
            return
        }

        #expect(!dueInsight.isResolved)
        #expect(dueInsight.preview == "Unresolved date")
    }

    @Test
    func normalizesDurationPreview() {
        let now = makeDate(year: 2026, month: 3, day: 2, hour: 9, minute: 30)
        let insights = analyzer.analyze("Review notes time:90m remind:2h", now: now)

        guard let timeInsight = insights.first(where: { $0.key == "time" }) else {
            #expect(Bool(false), "Expected time insight")
            return
        }

        guard let remindInsight = insights.first(where: { $0.key == "remind" }) else {
            #expect(Bool(false), "Expected remind insight")
            return
        }

        #expect(timeInsight.isResolved)
        #expect(remindInsight.isResolved)
        #expect(timeInsight.preview.hasPrefix("+90m -> "))
        #expect(remindInsight.preview.hasPrefix("+120m -> "))
    }

    @Test
    func rejectsUnsupportedDurationValues() {
        let insights = analyzer.analyze("Task dur:soon")

        guard let durationInsight = insights.first(where: { $0.key == "dur" }) else {
            #expect(Bool(false), "Expected duration insight")
            return
        }

        #expect(!durationInsight.isResolved)
        #expect(durationInsight.preview == "Unsupported duration")
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
