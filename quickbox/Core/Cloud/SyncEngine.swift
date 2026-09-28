import Foundation
import QuickboxCore

protocol CloudSyncAPI {
    func changes(since cursor: Int) async throws -> ChangesResponse
    func push(_ request: PushRequest) async throws -> PushResponse
}

struct SyncReport: Equatable {
    /// Local files replaced with a newer cloud version.
    var changedPaths: [String] = []
    /// Local files whose previous content was saved under `_conflicts/`.
    var conflictCopies: [String] = []
    /// Ops the server refused (e.g. the task was deleted elsewhere); they are dropped.
    var rejectedOps = 0
}

/// One sync pass: push queued local changes, then pull newer cloud files into the local folder.
/// The cloud copy is the source of truth; local content quickbox did not write is never lost.
final class SyncEngine {
    static let batchSize = 200

    private let api: CloudSyncAPI
    private let mirror: LocalMirror
    private let outbox: SyncOutbox
    private let stateStore: SyncStateStoring
    private let timeZone: () -> TimeZone
    private let now: () -> Date

    init(
        api: CloudSyncAPI,
        mirror: LocalMirror,
        outbox: SyncOutbox,
        stateStore: SyncStateStoring,
        timeZone: @escaping () -> TimeZone = { .current },
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.mirror = mirror
        self.outbox = outbox
        self.stateStore = stateStore
        self.timeZone = timeZone
        self.now = now
    }

    func sync() async throws -> SyncReport {
        var state = stateStore.load()
        var report = SyncReport()

        if !state.hasImportedLocalFiles {
            try await importLocalFiles(into: &state, report: &report)
        }

        try await pushPending(report: &report)

        // Edits made while we were pushing are not in the cloud yet; pulling now could briefly
        // replace them locally. Leave the pull to the next pass.
        guard outbox.count == 0 else { return report }

        let changes = try await api.changes(since: state.cursor)
        for file in changes.files {
            try apply(file, to: &state, report: &report)
        }
        state.cursor = changes.cursor
        state.lastSyncedAt = now()
        stateStore.save(state)
        return report
    }

    /// Records the current content of every file as known, after quickbox itself changed them.
    func noteLocalWrites() {
        guard let files = try? mirror.markdownFiles() else { return }
        var state = stateStore.load()
        for (path, content) in files {
            state.knownHashes[path] = LocalMirror.hash(content)
        }
        stateStore.save(state)
    }

    /// First sync on this device: upload files the cloud does not have; where both have a file,
    /// the cloud wins and a differing local copy is kept aside.
    private func importLocalFiles(into state: inout SyncState, report: inout SyncReport) async throws {
        let cloud = try await api.changes(since: 0)
        let cloudFiles = Dictionary(cloud.files.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        let localFiles = try mirror.markdownFiles()

        var imports: [SyncOp] = []
        for (path, content) in localFiles.sorted(by: { $0.key < $1.key }) where cloudFiles[path] == nil {
            imports.append(.importFile(opID: SyncOp.newOpID(), path: path, content: content))
            state.knownHashes[path] = LocalMirror.hash(content)
        }
        outbox.prepend(imports)

        for file in cloud.files {
            try apply(file, to: &state, report: &report)
        }
        state.cursor = cloud.cursor
        state.hasImportedLocalFiles = true
        stateStore.save(state)
    }

    private func pushPending(report: inout SyncReport) async throws {
        while true {
            let batch = outbox.peek(max: Self.batchSize)
            guard !batch.isEmpty else { return }
            let response = try await api.push(PushRequest(timeZone: timeZone().identifier, ops: batch))
            report.rejectedOps += response.results.filter { !$0.ok }.count
            // Refused ops can never succeed (unknown id, invalid value); retrying would block the queue.
            outbox.remove(opIDs: Set(response.results.map(\.opId)))
        }
    }

    private func apply(_ file: ChangesResponse.File, to state: inout SyncState, report: inout SyncReport) throws {
        let local = try mirror.read(file.path)
        if local == file.content {
            state.knownHashes[file.path] = LocalMirror.hash(file.content)
            return
        }
        if let local, state.knownHashes[file.path] != LocalMirror.hash(local) {
            // Changed outside quickbox since the last sync (or never synced): keep it.
            try mirror.saveConflictCopy(of: file.path, content: local, at: now())
            report.conflictCopies.append(file.path)
        }
        try mirror.write(file.path, content: file.content)
        state.knownHashes[file.path] = LocalMirror.hash(file.content)
        report.changedPaths.append(file.path)
    }
}
