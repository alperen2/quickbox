import Foundation
import QuickboxCore

/// Wraps the local writer: the capture is written locally as before and, while sync is on,
/// also recorded as an `add` op carrying the same task id so both copies describe one task.
nonisolated final class SyncingInboxWriter: InboxWriting, @unchecked Sendable {
    private let base: InboxWriting
    private let recorder: SyncRecording
    private let onLocalWrite: @Sendable () -> Void

    init(base: InboxWriting, recorder: SyncRecording, onLocalWrite: @escaping @Sendable () -> Void = {}) {
        self.base = base
        self.recorder = recorder
        self.onLocalWrite = onLocalWrite
    }

    func appendEntry(_ text: String, now: Date) throws {
        guard recorder.isRecording else {
            try base.appendEntry(text, now: now)
            return
        }

        // An explicit id token wins over any typed one, so local and cloud lines share it.
        let entry = "\(text) \(TaskIdentifier.metadataKey):\(TaskIdentifier.generate())"
        try base.appendEntry(entry, now: now)
        onLocalWrite()
        recorder.record(.add(opID: SyncOp.newOpID(), text: entry, capturedAt: CapturedAt(now)))
    }
}

/// Wraps the local repository: every successful mutation is also recorded as an op addressed by
/// the task's stable id. Lines without an id (never synced) are changed locally only.
nonisolated final class SyncingInboxRepository: InboxRepositorying, @unchecked Sendable {
    private let base: InboxRepositorying
    private let recorder: SyncRecording
    private let onLocalWrite: @Sendable () -> Void
    private let lock = NSLock()
    /// Where the last deleted task lived, to replay an undo as `insertLine`.
    private var lastDeleted: (path: String, taskID: String)?

    init(base: InboxRepositorying, recorder: SyncRecording, onLocalWrite: @escaping @Sendable () -> Void = {}) {
        self.base = base
        self.recorder = recorder
        self.onLocalWrite = onLocalWrite
    }

    var canUndoDelete: Bool { base.canUndoDelete }

    func load(on date: Date) throws -> [InboxItem] { try base.load(on: date) }
    func reload(on date: Date) throws -> [InboxItem] { try base.reload(on: date) }
    func loadToday() throws -> [InboxItem] { try base.loadToday() }
    func reload() throws -> [InboxItem] { try base.reload() }

    func apply(_ mutation: InboxMutation) throws -> [InboxItem] {
        try apply(mutation, on: Date())
    }

    func apply(_ mutation: InboxMutation, on date: Date) throws -> [InboxItem] {
        let items = try base.apply(mutation, on: date)
        guard recorder.isRecording else { return items }

        if let op = op(for: mutation, resultingItems: items) {
            onLocalWrite()
            recorder.record(op)
        }
        return items
    }

    private func op(for mutation: InboxMutation, resultingItems items: [InboxItem]) -> SyncOp? {
        switch mutation {
        case .toggle(let itemID):
            guard let taskID = Self.taskID(in: itemID), let item = items.first(where: { $0.id == itemID }) else { return nil }
            return .update(opID: SyncOp.newOpID(), taskID: taskID, patch: TaskPatch(done: item.isCompleted))

        case .edit(let itemID, let text):
            guard let taskID = Self.taskID(in: itemID) else { return nil }
            return .update(opID: SyncOp.newOpID(), taskID: taskID, patch: TaskPatch(text: text))

        case .setMetadata(let itemID, let key, let value):
            guard let taskID = Self.taskID(in: itemID) else { return nil }
            let patch = key.lowercased() == "due" ? TaskPatch(due: .some(value)) : TaskPatch(metadata: [key: value])
            return .update(opID: SyncOp.newOpID(), taskID: taskID, patch: patch)

        case .delete(let itemID):
            guard let taskID = Self.taskID(in: itemID), let path = Self.path(in: itemID) else { return nil }
            lock.withLock { lastDeleted = (path, taskID) }
            return .delete(opID: SyncOp.newOpID(), taskID: taskID)

        case .undoLastDelete:
            guard let deleted = lock.withLock({ lastDeleted }),
                  let restored = items.first(where: { $0.taskID == deleted.taskID }) else { return nil }
            lock.withLock { lastDeleted = nil }
            return .insertLine(opID: SyncOp.newOpID(), path: deleted.path, line: restored.rawLine)
        }
    }

    /// Item ids look like `<file>#id:<taskID>` once a line has a stable id.
    static func taskID(in itemID: String) -> String? {
        let marker = "#\(TaskIdentifier.metadataKey):"
        guard let range = itemID.range(of: marker, options: .backwards) else { return nil }
        let taskID = String(itemID[range.upperBound...])
        return TaskIdentifier.isValid(taskID) ? taskID : nil
    }

    static func path(in itemID: String) -> String? {
        itemID.components(separatedBy: "#").first.flatMap { $0.isEmpty ? nil : $0 }
    }
}
