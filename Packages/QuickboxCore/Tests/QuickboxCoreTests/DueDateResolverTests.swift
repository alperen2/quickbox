import Foundation
import Testing
@testable import QuickboxCore

struct DueDateResolverTests {
    @Test
    func dueDateResolverSupportsNaturalPhrases() throws {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 2
        comps.hour = 10
        comps.minute = 0
        let referenceDate = try #require(calendar.date(from: comps))

        let resolver = DueDateResolver()

        let nextWeekend = try #require(resolver.resolve(dueDateString: "next weekend", from: referenceDate))
        let endOfMonth = try #require(resolver.resolve(dueDateString: "end of month", from: referenceDate))
        let inTwoWeeks = try #require(resolver.resolve(dueDateString: "in 2 weeks", from: referenceDate))

        let weekendComponents = calendar.dateComponents([.year, .month, .day], from: nextWeekend)
        #expect(weekendComponents.year == 2026)
        #expect(weekendComponents.month == 3)
        #expect(weekendComponents.day == 7)

        let endOfMonthComponents = calendar.dateComponents([.year, .month, .day], from: endOfMonth)
        #expect(endOfMonthComponents.year == 2026)
        #expect(endOfMonthComponents.month == 3)
        #expect(endOfMonthComponents.day == 31)

        let inTwoWeeksComponents = calendar.dateComponents([.year, .month, .day], from: inTwoWeeks)
        #expect(inTwoWeeksComponents.year == 2026)
        #expect(inTwoWeeksComponents.month == 3)
        #expect(inTwoWeeksComponents.day == 16)
    }

    @Test
    func dueDateResolverDifferentiatesWeekdayAndNextWeekday() throws {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 2
        comps.hour = 10
        comps.minute = 0
        let referenceDate = try #require(calendar.date(from: comps))

        let resolver = DueDateResolver()
        let friday = try #require(resolver.resolve(dueDateString: "friday", from: referenceDate))
        let nextFriday = try #require(resolver.resolve(dueDateString: "next friday", from: referenceDate))

        let fridayComps = calendar.dateComponents([.year, .month, .day], from: friday)
        #expect(fridayComps.year == 2026)
        #expect(fridayComps.month == 3)
        #expect(fridayComps.day == 6)

        let nextFridayComps = calendar.dateComponents([.year, .month, .day], from: nextFriday)
        #expect(nextFridayComps.year == 2026)
        #expect(nextFridayComps.month == 3)
        #expect(nextFridayComps.day == 13)
    }

}
