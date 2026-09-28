/** Shapes exchanged with callers (MCP tools, sync API). Plain JSON, safe to cross the Durable Object RPC boundary. */

export type TaskStatus = "open" | "done" | "all";

export interface TaskQuery {
  /** A day (`today`, `2026-09-28`, `next friday`) using the app's day view; omit to search every task file. */
  date?: string;
  /** Matches the `for:` token, e.g. `agent` or `me`. */
  assignee?: string;
  status?: TaskStatus;
  project?: string;
  tag?: string;
}

export interface NewTask {
  /** A capture in quickbox syntax, e.g. `Publish post @Marketing due:tomorrow`. */
  text: string;
  due?: string;
  assignee?: string;
  /** `id:` of the task this one follows up on. */
  origin?: string;
  /** Related note path, e.g. `_notes/k3f9x2ab.md`. */
  ref?: string;
}

export interface TaskPatch {
  text?: string;
  /** `null` removes the due date. */
  due?: string | null;
  priority?: 1 | 2 | 3 | null;
  assignee?: string | null;
  ref?: string | null;
  done?: boolean;
}

export interface Task {
  /** Stable id; `null` for legacy lines written before ids existed (read-only through the API). */
  id: string | null;
  text: string;
  done: boolean;
  time: string;
  file: string;
  project: string | null;
  tags: string[];
  priority: number | null;
  due: string | null;
  /** Other tokens, including the handoff keys `for`, `by`, `from` and `ref`. */
  metadata: Record<string, string>;
}

export interface Note {
  path: string;
  content: string;
}

/** Who performs a write. Agents are named from their verified client identity, never from their input. */
export type Actor = { kind: "user" } | { kind: "agent"; name: string };
