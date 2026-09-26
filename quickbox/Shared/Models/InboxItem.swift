import Foundation

struct InboxItem: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    var tags: [String] = []
    var dueDate: String? = nil
    var priority: Int? = nil
    var projectName: String? = nil
    var metadata: [String: String] = [:] // Holds dynamic key:value pairs like time:30m
    var taskID: String? = nil // Stable `id:` token; nil for legacy lines written before ids existed
    let time: String
    let isCompleted: Bool
    let lineIndex: Int
    let rawLine: String
}

enum InboxMutation: Sendable {
    case toggle(String)
    case delete(String)
    case edit(String, text: String)
    /// Sets (or removes, when `value` is nil) a single `key:value` token without touching the rest of the line.
    case setMetadata(String, key: String, value: String?)
    case undoLastDelete
}

protocol InboxRepositorying: Sendable {
    func load(on date: Date) throws -> [InboxItem]
    func apply(_ mutation: InboxMutation, on date: Date) throws -> [InboxItem]
    func reload(on date: Date) throws -> [InboxItem]

    func loadToday() throws -> [InboxItem]
    func apply(_ mutation: InboxMutation) throws -> [InboxItem]
    func reload() throws -> [InboxItem]
    var canUndoDelete: Bool { get }
}
