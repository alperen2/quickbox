import { InboxError, type InboxErrorCode } from "./errors";
import type { Inbox } from "./inbox";
import type { Actor, NewTask, Note, Task, TaskPatch, TaskQuery } from "./types";

/**
 * Expected failures travel as values: Durable Object RPC keeps an error's message but not its
 * class, so callers could not tell a bad request from a server fault if these were thrown.
 */
export type InboxResult<T> = { ok: true; value: T } | { ok: false; error: { code: InboxErrorCode; message: string } };

/** The inbox as seen by transports (MCP, sync API); implemented by the `InboxStore` Durable Object. */
export interface InboxApi {
  listTasks(query: TaskQuery): Promise<InboxResult<Task[]>>;
  addTask(input: NewTask, actor: Actor): Promise<InboxResult<Task>>;
  updateTask(taskId: string, patch: TaskPatch): Promise<InboxResult<Task>>;
  completeTask(taskId: string): Promise<InboxResult<Task>>;
  readNote(path: string): Promise<InboxResult<Note>>;
  writeNote(path: string, content: string): Promise<InboxResult<Note>>;
}

export function capture<T>(operation: () => T): InboxResult<T> {
  try {
    return { ok: true, value: operation() };
  } catch (error) {
    if (error instanceof InboxError) return { ok: false, error: { code: error.code, message: error.message } };
    throw error;
  }
}

/** Serves an in-process `Inbox` through `InboxApi`, used by tests and any single-process host. */
export function localInboxApi(inbox: Inbox): InboxApi {
  return {
    listTasks: async (query) => capture(() => inbox.listTasks(query)),
    addTask: async (input, actor) => capture(() => inbox.addTask(input, actor)),
    updateTask: async (taskId, patch) => capture(() => inbox.updateTask(taskId, patch)),
    completeTask: async (taskId) => capture(() => inbox.completeTask(taskId)),
    readNote: async (path) => capture(() => inbox.readNote(path)),
    writeNote: async (path, content) => capture(() => inbox.writeNote(path, content)),
  };
}
