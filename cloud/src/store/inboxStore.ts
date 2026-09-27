import { DurableObject } from "cloudflare:workers";
import { isValidTimeZone, zonedNow } from "../core/calendar";
import { capture, type InboxApi } from "../inbox/api";
import { Inbox } from "../inbox/inbox";
import type { Actor, NewTask, TaskPatch, TaskQuery } from "../inbox/types";
import { SqlFileStore } from "./sqlFileStore";

/**
 * One instance per user. A Durable Object runs one request at a time and its SQLite calls are
 * synchronous, so every inbox operation (read file → change line → write file) is atomic even
 * when the Mac app, the phone and several agents write at once.
 */
export class InboxStore extends DurableObject<Env> implements InboxApi {
  private readonly inbox: Inbox;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const timeZone = isValidTimeZone(env.DEFAULT_TIMEZONE) ? env.DEFAULT_TIMEZONE : "UTC";
    this.inbox = new Inbox(new SqlFileStore(ctx.storage.sql), { now: () => zonedNow(timeZone) });
  }

  async listTasks(query: TaskQuery) {
    return capture(() => this.inbox.listTasks(query));
  }

  async addTask(input: NewTask, actor: Actor) {
    return capture(() => this.inbox.addTask(input, actor));
  }

  async updateTask(taskId: string, patch: TaskPatch) {
    return capture(() => this.inbox.updateTask(taskId, patch));
  }

  async completeTask(taskId: string) {
    return capture(() => this.inbox.completeTask(taskId));
  }

  async readNote(path: string) {
    return capture(() => this.inbox.readNote(path));
  }

  async writeNote(path: string, content: string) {
    return capture(() => this.inbox.writeNote(path, content));
  }
}
