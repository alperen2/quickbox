import { parseISODate, type LocalNow } from "../core/calendar";
import { capture } from "../inbox/api";
import type { Inbox } from "../inbox/inbox";
import type { SqlFileStore } from "../store/sqlFileStore";
import type { Sql } from "../store/sql";
import type { ChangesResponse, OpResult, SyncOp } from "./ops";

const APPLIED_OP_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * Applies device ops to one user's inbox and reports file changes. Runs inside the user's
 * `InboxStore`, synchronously, so a batch of ops and the version bump it causes are atomic.
 */
export class SyncService {
  constructor(
    private readonly sql: Sql,
    private readonly inbox: Inbox,
    private readonly files: SqlFileStore,
    private readonly now: () => number = Date.now,
  ) {
    sql.exec(`CREATE TABLE IF NOT EXISTS applied_ops (
      op_id TEXT PRIMARY KEY,
      result TEXT NOT NULL,
      applied_at INTEGER NOT NULL
    )`);
  }

  push(ops: readonly SyncOp[]): OpResult[] {
    const results = ops.map((op) => this.applyOnce(op));
    this.sql.exec("DELETE FROM applied_ops WHERE applied_at < ?", this.now() - APPLIED_OP_RETENTION_MS);
    return results;
  }

  changes(cursor: number): ChangesResponse {
    return { cursor: this.files.currentVersion(), files: this.files.changesSince(cursor) };
  }

  private applyOnce(op: SyncOp): OpResult {
    const previous = this.sql
      .exec<{ result: string }>("SELECT result FROM applied_ops WHERE op_id = ?", op.opId)
      .toArray()[0];
    if (previous) return JSON.parse(previous.result) as OpResult;

    const outcome = capture(() => this.apply(op));
    const result: OpResult = outcome.ok ? { opId: op.opId, ok: true } : { opId: op.opId, ok: false, error: outcome.error };
    this.sql.exec("INSERT INTO applied_ops (op_id, result, applied_at) VALUES (?, ?, ?)", op.opId, JSON.stringify(result), this.now());
    return result;
  }

  private apply(op: SyncOp): void {
    switch (op.type) {
      case "add": {
        const capturedAt: LocalNow = { date: parseISODate(op.capturedAt.date)!, time: op.capturedAt.time };
        this.inbox.addTask({ text: op.text }, { kind: "user" }, { capturedAt });
        return;
      }
      case "update":
        this.inbox.updateTask(op.taskId, op.patch);
        return;
      case "delete":
        this.inbox.deleteTask(op.taskId);
        return;
      case "insertLine":
        this.inbox.insertLine(op.path, op.line);
        return;
      case "importFile":
        this.inbox.importFile(op.path, op.content);
        return;
    }
  }
}
