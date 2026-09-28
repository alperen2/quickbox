import Foundation
import Testing
@testable import QuickboxCore

struct SyncModelsTests {

    /// `fixtures/sync-push-request.json` is also validated by the server's schema (cloud/test/sync.test.ts),
    /// so the app and the cloud cannot drift apart on the wire format.
    @Test
    func encodesOpsExactlyAsTheServerExpects() throws {
        let request = PushRequest(timeZone: "Europe/Istanbul", ops: Self.fixtureOps)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: FixtureLocation.url(named: "sync-push-request.json"))) as? NSDictionary

        #expect(encoded == expected)
    }

    @Test
    func decodesWhatItEncodesForTheOutbox() throws {
        let decoded = try JSONDecoder().decode([SyncOp].self, from: JSONEncoder().encode(Self.fixtureOps))

        #expect(decoded == Self.fixtureOps)
    }

    @Test
    func capturedAtUsesTheDevicesLocalDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 27
        components.hour = 21
        components.minute = 30
        components.timeZone = TimeZone(identifier: "UTC")
        let instant = Calendar(identifier: .gregorian).date(from: components)!

        // 21:30 UTC is already the next day in Istanbul (UTC+3).
        #expect(CapturedAt(instant, timeZone: TimeZone(identifier: "Europe/Istanbul")!) == CapturedAt(date: "2026-09-28", time: "00:30"))
    }

    private static let fixtureOps: [SyncOp] = [
        .importFile(opID: "0b5c8e4a-0000-4000-8000-000000000001", path: "2026-09-20.md", content: "- [ ] 08:00 Old local task\n"),
        .add(opID: "0b5c8e4a-0000-4000-8000-000000000002", text: "Buy milk #home id:mac00001",
             capturedAt: CapturedAt(date: "2026-09-28", time: "09:30")),
        .update(opID: "0b5c8e4a-0000-4000-8000-000000000003", taskID: "mac00001",
                patch: TaskPatch(due: .some(nil), done: true, metadata: ["remind": nil, "time": "1h"])),
        .update(opID: "0b5c8e4a-0000-4000-8000-000000000004", taskID: "mac00001", patch: TaskPatch(text: "Buy oat milk")),
        .delete(opID: "0b5c8e4a-0000-4000-8000-000000000005", taskID: "mac00001"),
        .insertLine(opID: "0b5c8e4a-0000-4000-8000-000000000006", path: "2026-09-28.md",
                    line: "- [ ] 09:30 Buy oat milk #home id:mac00001"),
    ]
}
