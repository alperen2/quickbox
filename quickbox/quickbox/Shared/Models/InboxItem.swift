import Foundation

struct InboxItem: Identifiable, Equatable {
    let id: String
    let text: String
    let time: String
    let isCompleted: Bool
    let lineIndex: Int
    let rawLine: String
}

enum InboxMutation {
    case toggle(String)
    case delete(String)
    case edit(String, text: String)
    case undoLastDelete
}

protocol InboxRepositorying {
    func load(on date: Date) throws -> [InboxItem]
    func apply(_ mutation: InboxMutation, on date: Date) throws -> [InboxItem]
    func reload(on date: Date) throws -> [InboxItem]

    func loadToday() throws -> [InboxItem]
    func apply(_ mutation: InboxMutation) throws -> [InboxItem]
    func reload() throws -> [InboxItem]
    var canUndoDelete: Bool { get }
}
