import Foundation

/// A local change a device replays on the cloud copy. Mirrors `cloud/src/sync/ops.ts`; the JSON shape is
/// pinned by `fixtures/sync-push-request.json`, which both sides test against.
public enum SyncOp: Equatable, Sendable {
    case add(opID: String, text: String, capturedAt: CapturedAt)
    case update(opID: String, taskID: String, patch: TaskPatch)
    case delete(opID: String, taskID: String)
    case insertLine(opID: String, path: String, line: String)
    case importFile(opID: String, path: String, content: String)

    public var opID: String {
        switch self {
        case .add(let opID, _, _), .update(let opID, _, _), .delete(let opID, _),
             .insertLine(let opID, _, _), .importFile(let opID, _, _):
            return opID
        }
    }

    public static func newOpID() -> String {
        UUID().uuidString.lowercased()
    }
}

/// The device's local day and wall-clock time when a task was captured.
public struct CapturedAt: Codable, Equatable, Sendable {
    public let date: String
    public let time: String

    public init(date: String, time: String) {
        self.date = date
        self.time = time
    }

    public init(_ instant: Date, timeZone: TimeZone = .current) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        date = formatter.string(from: instant)
        formatter.dateFormat = "HH:mm"
        time = formatter.string(from: instant)
    }
}

/// Fields to change on a task; a `.some(nil)` value clears the field on the server.
public struct TaskPatch: Equatable, Sendable {
    public var text: String?
    public var due: String??
    public var done: Bool?
    public var metadata: [String: String?]?

    public init(text: String? = nil, due: String?? = nil, done: Bool? = nil, metadata: [String: String?]? = nil) {
        self.text = text
        self.due = due
        self.done = done
        self.metadata = metadata
    }
}

extension TaskPatch: Encodable {
    private enum CodingKeys: String, CodingKey { case text, due, done, metadata }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(text, forKey: .text)
        if let due {
            // Encode an explicit null to clear, omit the key to leave it unchanged.
            try container.encode(due, forKey: .due)
        }
        try container.encodeIfPresent(done, forKey: .done)
        if let metadata {
            var nested = container.nestedContainer(keyedBy: DynamicKey.self, forKey: .metadata)
            for key in metadata.keys.sorted() {
                try nested.encode(metadata[key] ?? nil, forKey: DynamicKey(key))
            }
        }
    }
}

extension SyncOp: Encodable {
    private enum CodingKeys: String, CodingKey {
        case opId, type, text, capturedAt, taskId, patch, path, line, content
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opID, forKey: .opId)
        switch self {
        case .add(_, let text, let capturedAt):
            try container.encode("add", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(capturedAt, forKey: .capturedAt)
        case .update(_, let taskID, let patch):
            try container.encode("update", forKey: .type)
            try container.encode(taskID, forKey: .taskId)
            try container.encode(patch, forKey: .patch)
        case .delete(_, let taskID):
            try container.encode("delete", forKey: .type)
            try container.encode(taskID, forKey: .taskId)
        case .insertLine(_, let path, let line):
            try container.encode("insertLine", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(line, forKey: .line)
        case .importFile(_, let path, let content):
            try container.encode("importFile", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(content, forKey: .content)
        }
    }
}

/// Persisted form of queued ops (the outbox survives restarts and offline periods).
extension SyncOp: Decodable {
    private enum StoredKind: String, Codable { case add, update, delete, insertLine, importFile }

    private struct StoredPatch: Decodable {
        let text: String?
        let due: String??
        let done: Bool?
        let metadata: [String: String?]?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            text = try container.decodeIfPresent(String.self, forKey: DynamicKey("text"))
            due = container.contains(DynamicKey("due"))
                ? .some(try container.decodeIfPresent(String.self, forKey: DynamicKey("due")))
                : nil
            done = try container.decodeIfPresent(Bool.self, forKey: DynamicKey("done"))
            metadata = try container.decodeIfPresent([String: String?].self, forKey: DynamicKey("metadata"))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let opID = try container.decode(String.self, forKey: .opId)
        switch try container.decode(StoredKind.self, forKey: .type) {
        case .add:
            self = .add(opID: opID, text: try container.decode(String.self, forKey: .text),
                        capturedAt: try container.decode(CapturedAt.self, forKey: .capturedAt))
        case .update:
            let stored = try container.decode(StoredPatch.self, forKey: .patch)
            self = .update(opID: opID, taskID: try container.decode(String.self, forKey: .taskId),
                           patch: TaskPatch(text: stored.text, due: stored.due, done: stored.done, metadata: stored.metadata))
        case .delete:
            self = .delete(opID: opID, taskID: try container.decode(String.self, forKey: .taskId))
        case .insertLine:
            self = .insertLine(opID: opID, path: try container.decode(String.self, forKey: .path),
                               line: try container.decode(String.self, forKey: .line))
        case .importFile:
            self = .importFile(opID: opID, path: try container.decode(String.self, forKey: .path),
                               content: try container.decode(String.self, forKey: .content))
        }
    }
}

public struct PushRequest: Encodable, Sendable {
    public let timeZone: String
    public let ops: [SyncOp]

    public init(timeZone: String, ops: [SyncOp]) {
        self.timeZone = timeZone
        self.ops = ops
    }
}

public struct PushResponse: Decodable, Sendable {
    public struct Result: Decodable, Sendable {
        public struct Failure: Decodable, Sendable {
            public let code: String
            public let message: String

            public init(code: String, message: String) {
                self.code = code
                self.message = message
            }
        }

        public let opId: String
        public let ok: Bool
        public let error: Failure?

        public init(opId: String, ok: Bool, error: Failure? = nil) {
            self.opId = opId
            self.ok = ok
            self.error = error
        }
    }

    public let results: [Result]

    public init(results: [Result]) {
        self.results = results
    }
}

public struct ChangesResponse: Decodable, Sendable {
    public struct File: Decodable, Equatable, Sendable {
        public let path: String
        public let content: String
        public let version: Int

        public init(path: String, content: String, version: Int) {
            self.path = path
            self.content = content
            self.version = version
        }
    }

    public let cursor: Int
    public let files: [File]

    public init(cursor: Int, files: [File]) {
        self.cursor = cursor
        self.files = files
    }
}

struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
