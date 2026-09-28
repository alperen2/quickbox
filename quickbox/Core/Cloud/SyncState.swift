import Foundation

/// What this device knows about the cloud copy, persisted between launches.
nonisolated struct SyncState: Codable, Equatable, Sendable {
    /// Latest cloud file version applied locally; 0 before the first sync.
    var cursor: Int = 0
    /// Whether this device's pre-existing files were offered to the cloud.
    var hasImportedLocalFiles = false
    /// SHA-256 of each file's content as last synced (or written by the app), to spot edits made
    /// outside quickbox before overwriting a file with the cloud version.
    var knownHashes: [String: String] = [:]
    var lastSyncedAt: Date?
}

nonisolated protocol SyncStateStoring: Sendable {
    func load() -> SyncState
    func save(_ state: SyncState)
    func clear()
}

nonisolated final class FileSyncStateStore: SyncStateStoring, @unchecked Sendable {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> SyncState {
        guard let data = try? Data(contentsOf: fileURL), let state = try? JSONDecoder().decode(SyncState.self, from: data) else {
            return SyncState()
        }
        return state
    }

    func save(_ state: SyncState) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

nonisolated final class MemorySyncStateStore: SyncStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state = SyncState()

    func load() -> SyncState { lock.withLock { state } }
    func save(_ state: SyncState) { lock.withLock { self.state = state } }
    func clear() { lock.withLock { state = SyncState() } }
}
