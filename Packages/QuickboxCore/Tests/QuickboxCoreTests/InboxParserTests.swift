import Foundation
import Testing
@testable import QuickboxCore

struct InboxParserTests {
    @Test
    func parserReturnsOnlyValidTaskLines() {
        let parser = InboxParser()
        let lines = [
            "- [ ] 09:10 plan sprint",
            "random line",
            "- [x] 09:20 done item"
        ]

        let items = parser.parse(lines: lines, sourceID: "today.md")
        #expect(items.count == 2)
        #expect(items[0].isCompleted == false)
        #expect(items[1].isCompleted == true)
        #expect(items[0].lineIndex == 0)
        #expect(items[1].lineIndex == 2)
    }

    @Test
    func parserSupportsMultiWordDateMetadataValues() throws {
        let parser = InboxParser()
        let lines = [
            "- [ ] 09:10 Plan launch due:next friday defer:end of month start:in 2 weeks #ops @alpha !1"
        ]

        let items = parser.parse(lines: lines, sourceID: "today.md")
        let item = try #require(items.first)

        #expect(item.dueDate == "next friday")
        #expect(item.metadata["defer"] == "end of month")
        #expect(item.metadata["start"] == "in 2 weeks")
        #expect(item.tags == ["ops"])
        #expect(item.projectName == "alpha")
        #expect(item.priority == 1)
    }

    @Test
    func parserExposesTaskIDSeparatelyFromMetadata() throws {
        let items = InboxParser().parse(lines: ["- [ ] 08:00 Draft post #social time:30m id:k3f9x2ab"], sourceID: "2026-02-27.md")
        let item = try #require(items.first)

        #expect(item.taskID == "k3f9x2ab")
        #expect(item.metadata == ["time": "30m"])
        #expect(item.text == "Draft post")
        #expect(item.id == "2026-02-27.md#id:k3f9x2ab")
    }

    @Test
    func parserIdentityIsStableWhenLinesShift() {
        let parser = InboxParser()
        let line = "- [ ] 08:00 Draft post id:k3f9x2ab"
        let before = parser.parse(lines: [line], sourceID: "a.md")
        let after = parser.parse(lines: ["- [ ] 07:00 inserted by another device", line], sourceID: "a.md")

        #expect(before.first?.id == after.last?.id)
    }

    @Test
    func parserOnlyTrustsFirstOccurrenceOfDuplicatedTaskID() {
        let items = InboxParser().parse(
            lines: ["- [ ] 08:00 original id:dup00001", "- [ ] 09:00 pasted copy id:dup00001"],
            sourceID: "a.md"
        )

        #expect(items.count == 2)
        #expect(items[0].taskID == "dup00001")
        #expect(items[1].taskID == nil)
        #expect(items[0].id != items[1].id)
    }

    @Test
    func generatedTaskIDsUseLowercaseAlphanumerics() {
        let id = TaskIdentifier.generate()
        #expect(id.count == TaskIdentifier.length)
        #expect(id.allSatisfy { $0.isLowercase || $0.isNumber })
        #expect(TaskIdentifier.isValid(id))
    }

}
