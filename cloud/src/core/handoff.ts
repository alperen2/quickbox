/**
 * Metadata keys that let people and agents hand tasks to each other.
 * Mirrors `TaskHandoff.swift`; they are ordinary `key:value` tokens.
 */
export const HandoffKey = {
  /** Who should act: `me`, `agent`, or a specific agent name. */
  assignee: "for",
  /** Who wrote the line. Absent means the user wrote it. */
  author: "by",
  /** `id:` of the task this one was spawned from. */
  origin: "from",
  /** Path of a related note, e.g. an agent's draft under `_notes/`. */
  reference: "ref",
} as const;

export const Assignee = {
  me: "me",
  agent: "agent",
} as const;
