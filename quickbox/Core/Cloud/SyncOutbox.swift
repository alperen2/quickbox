import Foundation
import QuickboxCore

/// Receives local changes while cloud sync is on. Called from the storage decorators, which may
/// run off the main thread.
nonisolated protocol SyncRecording: AnyObject, Sendable {
    var isRecording: Bool { get }
    func record(_ op: SyncOp)
}

/// Ops waiting to be pushed, persisted as JSON so offline changes survive a restart.
/// Thread-safe: storage mutations enqueue from a background queue, the engine drains on main.
nonisolated final class SyncOutbox: SyncRecording, @unchecked Sendable {
    private let fileURL: URL?
    private let lock = NSLock()
    private var ops: [SyncOp]
    private var recording: Bool
    private let onRecord: @Sendable () -> Void

    /// - Parameters:
    ///   - fileURL: where the queue is persisted; `nil` keeps it in memory (tests).
    ///   - onRecord: called after each recorded op, e.g. to schedule a sync.
    init(fileURL: URL?, isRecording: Bool = false, onRecord: @escaping @Sendable () -> Void = {}) {
        self.fileURL = fileURL
        self.recording = isRecording
        self.onRecord = onRecord
        if let fileURL, let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode([SyncOp].self, from: data) {
            ops = stored
        } else {
            ops = []
        }
    }

    var isRecording: Bool {
        lock.withLock { recording }
    }

    func setRecording(_ enabled: Bool) {
        lock.withLock { recording = enabled }
    }

    var count: Int {
        lock.withLock { ops.count }
    }

    func record(_ op: SyncOp) {
        guard isRecording else { return }
        enqueue([op])
        onRecord()
    }

    func enqueue(_ newOps: [SyncOp]) {
        lock.withLock {
            ops.append(contentsOf: newOps)
            persistLocked()
        }
    }

    /// Puts ops ahead of everything already queued (e.g. the initial import before later edits).
    func prepend(_ newOps: [SyncOp]) {
        lock.withLock {
            ops.insert(contentsOf: newOps, at: 0)
            persistLocked()
        }
    }

    func peek(max: Int) -> [SyncOp] {
        lock.withLock { Array(ops.prefix(max)) }
    }

    func remove(opIDs: Set<String>) {
        lock.withLock {
            ops.removeAll { opIDs.contains($0.opID) }
            persistLocked()
        }
    }

    func removeAll() {
        lock.withLock {
            ops.removeAll()
            persistLocked()
        }
    }

    private func persistLocked() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ops).write(to: fileURL, options: .atomic)
        } catch {
            // Keeping the in-memory queue is the best we can do; the next write retries persisting.
        }
    }
}
