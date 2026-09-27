import { DurableObject } from "cloudflare:workers";
import { isValidTimeZone, zonedNow } from "../core/calendar";
import { capture, type InboxApi } from "../inbox/api";
import { Inbox } from "../inbox/inbox";
import type { Actor, NewTask, TaskPatch, TaskQuery } from "../inbox/types";
import type { PushRequest } from "../sync/ops";
import { SyncService } from "../sync/syncService";
import { SqlFileStore } from "./sqlFileStore";
import { UserSettings } from "./userSettings";

/**
 * One instance per user. A Durable Object runs one request at a time and its SQLite calls are
 * synchronous, so every inbox operation (read file → change line → write file) is atomic even
 * when the Mac app, the phone and several agents write at once.
 */
export class InboxStore extends DurableObject<Env> implements InboxApi {
  private readonly inbox: Inbox;
  private readonly settings: UserSettings;
  private readonly sync: SyncService;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const fallbackTimeZone = isValidTimeZone(env.DEFAULT_TIMEZONE) ? env.DEFAULT_TIMEZONE : "UTC";
    const files = new SqlFileStore(ctx.storage.sql);
    this.settings = new UserSettings(ctx.storage.sql);
    this.inbox = new Inbox(files, { now: () => zonedNow(this.settings.timeZone() ?? fallbackTimeZone) });
    this.sync = new SyncService(ctx.storage.sql, this.inbox, files);
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

  /** Device sync: apply a batch of already-validated ops. */
  async syncPush(request: PushRequest) {
    return this.ctx.storage.transactionSync(() => {
      if (request.timeZone) this.settings.setTimeZone(request.timeZone);
      return this.sync.push(request.ops);
    });
  }

  async syncChanges(cursor: number) {
    return this.sync.changes(cursor);
  }
}
