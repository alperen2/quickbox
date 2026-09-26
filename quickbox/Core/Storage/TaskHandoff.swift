import Foundation

/// Metadata keys that let people and agents hand tasks to each other in plain Markdown.
///
///     - [ ] 09:12 Create Instagram post id:k3f9x2ab for:agent
///     - [ ] 11:40 Publish post id:p7a2m1cd for:me by:claude from:k3f9x2ab ref:notes/k3f9x2ab.md
///
/// They are ordinary `key:value` tokens, so the parser needs no special casing and
/// existing files stay valid. Keep this list in sync with `fixtures/task-lines.json`.
nonisolated enum TaskHandoffKey {
    /// Who should act on the task: `me`, `agent`, or a specific agent name.
    static let assignee = "for"
    /// Who wrote the line. Absent means the user wrote it.
    static let author = "by"
    /// `id:` of the task this one was spawned from.
    static let origin = "from"
    /// Path of a related note inside the storage folder, e.g. an agent's draft.
    static let reference = "ref"
}

nonisolated enum TaskAssignee {
    static let me = "me"
    static let agent = "agent"

    static let suggestions = [me, agent]
}
