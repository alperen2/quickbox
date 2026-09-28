import Foundation
import QuickboxCore
import Testing
@testable import quickbox

// MARK: - Test doubles

private struct FolderResolver: StorageResolving {
    let baseURL: URL
    func resolvedBaseURL() throws -> URL { baseURL }
    func stopAccess(for url: URL) {}
}

@MainActor
private final class TempFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    init(files: [String: String] = [:]) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (path, content) in files { try write(path, content) }
    }

    func write(_ path: String, _ content: String) throws {
        let fileURL = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: url.appendingPathComponent(path), encoding: .utf8)
    }

    func conflictCopies() -> [String] {
        let folder = url.appendingPathComponent(LocalMirror.conflictsFolder)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// A scripted cloud: holds files with versions, records pushes, and lets tests change files "remotely".
@MainActor
private final class FakeCloud: CloudSyncAPI {
    var files: [String: (content: String, version: Int)] = [:]
    var version = 0
    var pushes: [PushRequest] = []
    var rejectOpIDs: Set<String> = []
    var onPush: (() -> Void)?

    func remoteWrite(_ path: String, _ content: String) {
        version += 1
        files[path] = (content, version)
    }

    func changes(since cursor: Int) async throws -> ChangesResponse {
        let changed = files
            .filter { cursor == 0 || $0.value.version > cursor }
            .map { ChangesResponse.File(path: $0.key, content: $0.value.content, version: $0.value.version) }
            .sorted { $0.version < $1.version }
        return ChangesResponse(cursor: version, files: changed)
    }

    func push(_ request: PushRequest) async throws -> PushResponse {
        pushes.append(request)
        for op in request.ops {
            if case .importFile(_, let path, let content) = op, files[path] == nil {
                remoteWrite(path, content)
            }
        }
        onPush?()
        return PushResponse(results: request.ops.map {
            PushResponse.Result(opId: $0.opID, ok: !rejectOpIDs.contains($0.opID))
        })
    }
}

@MainActor
private func makeEngine(folder: TempFolder, cloud: FakeCloud, outbox: SyncOutbox = SyncOutbox(fileURL: nil, isRecording: true)) -> (SyncEngine, SyncOutbox, MemorySyncStateStore) {
    let state = MemorySyncStateStore()
    let engine = SyncEngine(
        api: cloud,
        mirror: LocalMirror(storageResolver: FolderResolver(baseURL: folder.url)),
        outbox: outbox,
        stateStore: state,
        timeZone: { TimeZone(identifier: "Europe/Istanbul")! }
    )
    return (engine, outbox, state)
}

// MARK: - Sync engine

@MainActor
struct SyncEngineTests {

    @Test
    func firstSyncUploadsLocalOnlyFilesAndKeepsDifferingLocalCopies() async throws {
        let folder = try TempFolder(files: [
            "2026-09-20.md": "- [ ] 08:00 Only on this Mac\n",
            "2026-09-28.md": "- [ ] 08:00 Local version\n",
            "_notes/idea.md": "an idea",
            "Marketing/2026-09-20.md": "- [ ] 09:00 Project task @Marketing\n",
        ])
        let cloud = FakeCloud()
        cloud.remoteWrite("2026-09-28.md", "- [ ] 07:00 From an agent id:agent001\n")
        let (engine, _, state) = makeEngine(folder: folder, cloud: cloud)

        let report = try await engine.sync()

        let imported = cloud.pushes.flatMap(\.ops).compactMap { op -> String? in
            if case .importFile(_, let path, _) = op { return path } else { return nil }
        }
        #expect(imported.sorted() == ["2026-09-20.md", "Marketing/2026-09-20.md", "_notes/idea.md"])
        #expect(cloud.pushes.first?.timeZone == "Europe/Istanbul")
        #expect(folder.read("2026-09-28.md") == "- [ ] 07:00 From an agent id:agent001\n")
        #expect(report.conflictCopies == ["2026-09-28.md"])
        #expect(folder.conflictCopies().count == 1)
        #expect(state.load().hasImportedLocalFiles)
        #expect(state.load().cursor == cloud.version)
    }

    @Test
    func laterSyncsReplaceUnchangedFilesSilently() async throws {
        let folder = try TempFolder()
        let cloud = FakeCloud()
        let (engine, _, _) = makeEngine(folder: folder, cloud: cloud)
        cloud.remoteWrite("2026-09-28.md", "- [ ] 07:00 First id:agent001\n")
        _ = try await engine.sync()

        cloud.remoteWrite("2026-09-28.md", "- [x] 07:00 First id:agent001\n")
        let report = try await engine.sync()

        #expect(report.changedPaths == ["2026-09-28.md"])
        #expect(report.conflictCopies.isEmpty)
        #expect(folder.read("2026-09-28.md") == "- [x] 07:00 First id:agent001\n")
    }

    @Test
    func keepsFilesEditedOutsideQuickboxBeforeOverwriting() async throws {
        let folder = try TempFolder()
        let cloud = FakeCloud()
        let (engine, _, _) = makeEngine(folder: folder, cloud: cloud)
        cloud.remoteWrite("2026-09-28.md", "- [ ] 07:00 First id:agent001\n")
        _ = try await engine.sync()

        try folder.write("2026-09-28.md", "- [ ] 07:00 First id:agent001\nEdited in another editor\n")
        cloud.remoteWrite("2026-09-28.md", "- [x] 07:00 First id:agent001\n")
        let report = try await engine.sync()

        #expect(report.conflictCopies == ["2026-09-28.md"])
        #expect(folder.conflictCopies().count == 1)
        #expect(folder.read("2026-09-28.md") == "- [x] 07:00 First id:agent001\n")
    }

    @Test
    func changesMadeByQuickboxAreNotTreatedAsConflicts() async throws {
        let folder = try TempFolder()
        let cloud = FakeCloud()
        let (engine, outbox, _) = makeEngine(folder: folder, cloud: cloud)
        cloud.remoteWrite("2026-09-28.md", "- [ ] 07:00 First id:agent001\n")
        _ = try await engine.sync()

        // The app edits the file locally, records the op and notes the write.
        try folder.write("2026-09-28.md", "- [x] 07:00 First id:agent001\n")
        outbox.record(.update(opID: SyncOp.newOpID(), taskID: "agent001", patch: TaskPatch(done: true)))
        engine.noteLocalWrites()
        cloud.onPush = { cloud.remoteWrite("2026-09-28.md", "- [x] 07:00 First id:agent001\n- [ ] 08:00 Agent follow-up id:agent002\n") }
        let report = try await engine.sync()

        #expect(report.conflictCopies.isEmpty)
        #expect(folder.read("2026-09-28.md")?.contains("Agent follow-up") == true)
        #expect(outbox.count == 0)
    }

    @Test
    func dropsOpsTheCloudRejectsSoTheQueueNeverBlocks() async throws {
        let folder = try TempFolder()
        let cloud = FakeCloud()
        let (engine, outbox, _) = makeEngine(folder: folder, cloud: cloud)
        _ = try await engine.sync()
        let rejected = SyncOp.delete(opID: "rejected-op-1", taskID: "gone0001")
        outbox.record(rejected)
        outbox.record(.delete(opID: "accepted-op-1", taskID: "task0001"))
        cloud.rejectOpIDs = ["rejected-op-1"]

        let report = try await engine.sync()

        #expect(report.rejectedOps == 1)
        #expect(outbox.count == 0)
    }

    @Test
    func postponesPullWhenNewChangesArriveDuringPush() async throws {
        let folder = try TempFolder()
        let cloud = FakeCloud()
        let (engine, outbox, state) = makeEngine(folder: folder, cloud: cloud)
        _ = try await engine.sync()
        let cursorBefore = state.load().cursor
        outbox.record(.delete(opID: "first-op-1", taskID: "task0001"))
        cloud.onPush = {
            cloud.onPush = nil
            outbox.record(.delete(opID: "late-op-01", taskID: "task0002"))
        }

        _ = try await engine.sync()

        #expect(outbox.count == 0) // the late op is pushed in the same pass
        #expect(state.load().cursor >= cursorBefore)
    }
}

// MARK: - Layout

@MainActor
struct SyncLayoutTests {

    @Test
    func mirrorsProjectFoldersAndNotesButNotConflictCopiesOrHiddenFiles() throws {
        let folder = try TempFolder(files: [
            "2026-09-28.md": "inbox",
            "Marketing/2026-09-28.md": "project",
            "_notes/k3f9x2ab.md": "note",
            "_conflicts/2026-09-28 20260928-101010.md": "kept copy",
            ".hidden.md": "hidden",
        ])

        let files = try LocalMirror(storageResolver: FolderResolver(baseURL: folder.url)).markdownFiles()

        #expect(files.keys.sorted() == ["2026-09-28.md", "Marketing/2026-09-28.md", "_notes/k3f9x2ab.md"])
    }

    @Test
    func systemFoldersAreNeverProjects() throws {
        let folder = try TempFolder(files: ["Marketing/2026-09-28.md": "", "_notes/a.md": "", "_conflicts/b.md": ""])

        let projects = try StorageLayout.projectDirectories(in: folder.url).map(\.lastPathComponent)

        #expect(projects == ["Marketing"])
    }
}

// MARK: - Outbox

@MainActor
struct SyncOutboxTests {

    @Test
    func persistsQueuedOpsAcrossLaunches() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/outbox.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let ops: [SyncOp] = [
            .add(opID: "op-add-0001", text: "Buy milk id:mac00001", capturedAt: CapturedAt(date: "2026-09-28", time: "09:30")),
            .update(opID: "op-upd-0001", taskID: "mac00001", patch: TaskPatch(due: .some(nil), done: true, metadata: ["time": "1h", "remind": nil])),
        ]

        SyncOutbox(fileURL: fileURL, isRecording: true).enqueue(ops)
        let reopened = SyncOutbox(fileURL: fileURL)

        #expect(reopened.peek(max: 10) == ops)
    }

    @Test
    func ignoresChangesWhileNotRecording() {
        let outbox = SyncOutbox(fileURL: nil, isRecording: false)

        outbox.record(.delete(opID: "op-del-0001", taskID: "task0001"))

        #expect(outbox.count == 0)
    }
}

// MARK: - Storage decorators

@MainActor
struct SyncingStorageTests {

    private final class RecordingWriter: InboxWriting {
        var entries: [String] = []
        func appendEntry(_ text: String, now: Date) throws { entries.append(text) }
    }

    @Test
    func captureGetsAStableIdSharedByTheLocalLineAndTheAddOp() throws {
        let base = RecordingWriter()
        let outbox = SyncOutbox(fileURL: nil, isRecording: true)
        let writer = SyncingInboxWriter(base: base, recorder: outbox)

        try writer.appendEntry("Buy milk #home", now: Date())

        let entry = try #require(base.entries.first)
        guard case .add(_, let text, _) = try #require(outbox.peek(max: 1).first) else {
            Issue.record("Expected an add op")
            return
        }
        #expect(text == entry)
        #expect(entry.range(of: #"^Buy milk #home id:[a-z0-9]{8}$"#, options: .regularExpression) != nil)
    }

    @Test
    func writesLocallyOnlyWhileNotRecording() throws {
        let base = RecordingWriter()
        let outbox = SyncOutbox(fileURL: nil, isRecording: false)

        try SyncingInboxWriter(base: base, recorder: outbox).appendEntry("Buy milk", now: Date())

        #expect(base.entries == ["Buy milk"])
        #expect(outbox.count == 0)
    }

    @Test
    func repositoryMutationsBecomeOpsAddressedByTaskId() throws {
        let folder = try TempFolder()
        let dayFile = Self.todayFileName()
        try folder.write(dayFile, "- [ ] 08:00 Draft time:30m id:task0001\n- [ ] 09:00 Legacy without id\n")
        let outbox = SyncOutbox(fileURL: nil, isRecording: true)
        let repository = SyncingInboxRepository(base: InboxRepository(storageResolver: FolderResolver(baseURL: folder.url)), recorder: outbox)
        let itemID = "\(dayFile)#id:task0001"
        let legacy = try #require(try repository.loadToday().first { $0.taskID == nil })

        _ = try repository.apply(.toggle(itemID))
        _ = try repository.apply(.edit(itemID, text: "Final draft"))
        _ = try repository.apply(.setMetadata(itemID, key: "time", value: "1h"))
        _ = try repository.apply(.setMetadata(itemID, key: "due", value: nil))
        _ = try repository.apply(.toggle(legacy.id)) // no id: local only
        _ = try repository.apply(.delete(itemID))
        _ = try repository.apply(.undoLastDelete)

        let ops = outbox.peek(max: 10)
        #expect(ops.count == 6)
        guard ops.count == 6,
              case .update(_, "task0001", let done) = ops[0],
              case .update(_, "task0001", let text) = ops[1],
              case .update(_, "task0001", let time) = ops[2],
              case .update(_, "task0001", let due) = ops[3],
              case .delete(_, "task0001") = ops[4],
              case .insertLine(_, let path, let line) = ops[5] else {
            Issue.record("Unexpected ops: \(ops)")
            return
        }
        #expect(done == TaskPatch(done: true))
        #expect(text == TaskPatch(text: "Final draft"))
        #expect(time == TaskPatch(metadata: ["time": "1h"]))
        #expect(due == TaskPatch(due: .some(nil)))
        #expect(path == dayFile)
        #expect(line == "- [x] 08:00 Final draft time:1h id:task0001")
    }

    @Test
    func extractsTaskIdsOnlyFromStableItemIds() {
        #expect(SyncingInboxRepository.taskID(in: "2026-09-28.md#id:k3f9x2ab") == "k3f9x2ab")
        #expect(SyncingInboxRepository.taskID(in: "2026-09-28.md#3#- [ ] 08:00 Legacy") == nil)
        #expect(SyncingInboxRepository.path(in: "Marketing.md#id:k3f9x2ab") == "Marketing.md")
    }

    private static func todayFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date()) + ".md"
    }
}

// MARK: - Authentication

/// Serialized: the tests share `StubURLProtocol`'s static handler.
@MainActor
@Suite(.serialized)
struct CloudAuthenticatorTests {

    private final class MemoryTokenStore: CloudTokenStoring {
        var tokens: CloudTokens?
        func load() -> CloudTokens? { tokens }
        func save(_ tokens: CloudTokens) { self.tokens = tokens }
        func clear() { tokens = nil }
    }

    /// Plays the browser: answers the authorization URL with a scripted callback.
    private final class FakeWeb: WebAuthenticating {
        var respond: (URL) -> URL
        var openedURL: URL?
        init(respond: @escaping (URL) -> URL) { self.respond = respond }
        func authenticate(url: URL, callbackScheme: String) async throws -> URL {
            openedURL = url
            return respond(url)
        }
    }

    @Test
    func codeChallengeMatchesTheRFC7636Example() {
        // RFC 7636, Appendix B.
        #expect(CloudAuthenticator.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test
    func signInExchangesTheCodeWithPKCEAndStoresTokens() async throws {
        let stub = StubServer()
        defer { stub.stop() }
        var tokenForm: [String: String] = [:]
        stub.handler = { request in
            if request.url?.path == "/app/config" { return (200, StubServer.appConfig) }
            tokenForm = StubServer.form(of: request)
            return (200, #"{"access_token":"access-1","refresh_token":"refresh-1","expires_in":3600,"token_type":"bearer"}"#)
        }
        let store = MemoryTokenStore()
        let web = FakeWeb { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "quickbox://oauth/callback?code=code-1&state=\(state)")!
        }
        let authenticator = CloudAuthenticator(baseURL: StubServer.baseURL, urlSession: stub.session, tokenStore: store, web: web)

        try await authenticator.signIn()

        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: web.openedURL!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        #expect(query["client_id"] == "app-client")
        #expect(query["code_challenge_method"] == "S256")
        #expect(tokenForm["grant_type"] == "authorization_code")
        #expect(tokenForm["code"] == "code-1")
        #expect(CloudAuthenticator.codeChallenge(for: tokenForm["code_verifier"] ?? "") == query["code_challenge"])
        #expect(store.tokens?.accessToken == "access-1")
    }

    @Test
    func rejectsACallbackWithAnotherState() async {
        let stub = StubServer()
        defer { stub.stop() }
        stub.handler = { _ in (200, StubServer.appConfig) }
        let web = FakeWeb { _ in URL(string: "quickbox://oauth/callback?code=stolen&state=forged")! }
        let authenticator = CloudAuthenticator(baseURL: StubServer.baseURL, urlSession: stub.session, tokenStore: MemoryTokenStore(), web: web)

        await #expect(throws: CloudAuthError.invalidCallback) { try await authenticator.signIn() }
    }

    @Test
    func refreshesExpiringTokensAndSignsOutWhenTheGrantIsGone() async throws {
        let stub = StubServer()
        defer { stub.stop() }
        var refreshCalls = 0
        stub.handler = { request in
            if request.url?.path == "/app/config" { return (200, StubServer.appConfig) }
            refreshCalls += 1
            return refreshCalls == 1
                ? (200, #"{"access_token":"access-2","refresh_token":"refresh-2","expires_in":3600}"#)
                : (400, #"{"error":"invalid_grant"}"#)
        }
        let store = MemoryTokenStore()
        store.tokens = CloudTokens(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(30))
        let authenticator = CloudAuthenticator(baseURL: StubServer.baseURL, urlSession: stub.session, tokenStore: store, web: FakeWeb { $0 })

        #expect(try await authenticator.accessToken() == "access-2")
        #expect(store.tokens?.refreshToken == "refresh-2")
        await #expect(throws: CloudAuthError.signedOut) { try await authenticator.refresh() }
        #expect(store.tokens == nil)
    }
}

/// Routes a URLSession to an in-process handler (one active stub at a time).
private final class StubServer {
    static let baseURL = URL(string: "https://cloud.test")!
    static let appConfig = #"{"clientId":"app-client","redirectUri":"quickbox://oauth/callback","authorizationEndpoint":"https://cloud.test/authorize","tokenEndpoint":"https://cloud.test/oauth/token","resource":"https://cloud.test/mcp","scope":"inbox"}"#

    var handler: (URLRequest) -> (Int, String) = { _ in (404, "{}") } {
        didSet { StubURLProtocol.handler = handler }
    }

    let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }()

    func stop() { StubURLProtocol.handler = nil }

    static func form(of request: URLRequest) -> [String: String] {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let items = URLComponents(string: "?" + String(decoding: body, as: UTF8.self))?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (500, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
