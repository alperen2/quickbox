import Foundation
import QuickboxCore

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
