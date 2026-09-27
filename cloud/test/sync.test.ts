import { describe, expect, it } from "vitest";
import type { LocalNow } from "../src/core/calendar";
import { Inbox } from "../src/inbox/inbox";
import { SqlFileStore } from "../src/store/sqlFileStore";
import { pushRequestSchema, type SyncOp } from "../src/sync/ops";
import { SyncService } from "../src/sync/syncService";
import { memorySql } from "./sqlite";

const NOW: LocalNow = { date: { year: 2026, month: 9, day: 28 }, time: "09:12" };

function makeSync(files: Record<string, string> = {}) {
  const sql = memorySql();
  const store = new SqlFileStore(sql);
  for (const [path, content] of Object.entries(files)) store.write(path, content);
  let counter = 0;
  const inbox = new Inbox(store, { now: () => NOW }, () => `gen${String(++counter).padStart(5, "0")}`);
  return { sync: new SyncService(sql, inbox, store), store, inbox };
}

const op = <T extends SyncOp["type"]>(type: T, fields: Omit<Extract<SyncOp, { type: T }>, "type" | "opId">, opId = `op-${type}-1`) =>
  ({ opId, type, ...fields }) as Extract<SyncOp, { type: T }>;

describe("SyncService.push", () => {
  it("adds a capture with the device's id and capture time, written as the user", () => {
    const { sync, store } = makeSync();

    const [result] = sync.push([
      op("add", { text: "Buy milk #home for:agent id:dev00001", capturedAt: { date: "2026-09-27", time: "23:58" } }),
    ]);

    expect(result).toEqual({ opId: "op-add-1", ok: true });
    // Captured before midnight on the device: stays on that day even if it syncs later.
    expect(store.read("2026-09-27.md")).toBe("- [ ] 23:58 Buy milk #home for:agent id:dev00001\n");
  });

  it("applies each op once, even when a retry resends it", () => {
    const { sync, store } = makeSync();
    const add = op("add", { text: "Once id:dev00001", capturedAt: { date: "2026-09-28", time: "09:00" } });

    const first = sync.push([add]);
    const retry = sync.push([add]);

    expect(retry).toEqual(first);
    expect(store.read("2026-09-28.md")).toBe("- [ ] 09:00 Once id:dev00001\n");
  });

  it("updates, deletes and restores tasks by id", () => {
    const { sync, store } = makeSync({ "2026-09-28.md": "- [ ] 08:00 Draft time:30m id:task0001\n- [ ] 09:00 Other id:task0002\n" });

    sync.push([
      op("update", { taskId: "task0001", patch: { done: true, metadata: { time: "1h", remind: "15m" } } }),
      op("delete", { taskId: "task0002" }),
    ]);
    expect(store.read("2026-09-28.md")).toBe("- [x] 08:00 Draft remind:15m time:1h id:task0001\n");

    sync.push([op("insertLine", { path: "2026-09-28.md", line: "- [ ] 09:00 Other id:task0002" })]);
    expect(store.read("2026-09-28.md")).toBe("- [x] 08:00 Draft remind:15m time:1h id:task0001\n- [ ] 09:00 Other id:task0002\n");
  });

  it("reports failures per op and keeps going", () => {
    const { sync, store } = makeSync();

    const results = sync.push([
      op("delete", { taskId: "missing1" }, "op-a"),
      op("add", { text: "Still added id:dev00002", capturedAt: { date: "2026-09-28", time: "09:00" } }, "op-b"),
      op("update", { taskId: "dev00002", patch: { metadata: { id: "hijack" } } }, "op-c"),
    ]);

    expect(results.map((r) => r.ok)).toEqual([false, true, false]);
    expect(store.read("2026-09-28.md")).toBe("- [ ] 09:00 Still added id:dev00002\n");
  });

  it("imports a device's files once, giving legacy lines ids and never overwriting cloud files", () => {
    const { sync, store } = makeSync({ "2026-09-28.md": "- [ ] 07:00 From an agent id:agent001\n" });

    sync.push([
      op("importFile", { path: "2026-09-20.md", content: "# Notes\r\n- [ ] 08:00 Legacy\n- [x] 09:00 Has id id:keep0001\n- [ ] 10:00 Pasted id:keep0001\n" }, "op-1"),
      op("importFile", { path: "2026-09-28.md", content: "- [ ] 08:00 Local version\n" }, "op-2"),
      op("importFile", { path: "notes/idea.md", content: "- [ ] 00:00 not a task file" }, "op-3"),
    ]);

    expect(store.read("2026-09-20.md")).toBe(
      "# Notes\n- [ ] 08:00 Legacy id:gen00001\n- [x] 09:00 Has id id:keep0001\n- [ ] 10:00 Pasted id:gen00002\n",
    );
    expect(store.read("2026-09-28.md")).toBe("- [ ] 07:00 From an agent id:agent001\n");
    expect(store.read("notes/idea.md")).toBe("- [ ] 00:00 not a task file\n");
  });

  it("rejects unsafe file names", () => {
    const { sync } = makeSync();

    const results = sync.push([
      op("importFile", { path: "../escape.md", content: "" }, "op-1"),
      op("importFile", { path: ".hidden.md", content: "" }, "op-2"),
      op("insertLine", { path: "sub/dir.md", line: "- [ ] 08:00 x id:abc12345" }, "op-3"),
    ]);

    expect(results.every((r) => !r.ok)).toBe(true);
  });
});

describe("SyncService.changes", () => {
  it("returns everything first, then only newer versions", () => {
    const { sync, store } = makeSync({ "a.md": "a\n", "b.md": "b\n" });

    const initial = sync.changes(0);
    store.write("b.md", "b2\n");
    const next = sync.changes(initial.cursor);

    expect(initial.files.map((f) => f.path)).toEqual(["a.md", "b.md"]);
    expect(next.files).toEqual([{ path: "b.md", content: "b2\n", version: next.cursor }]);
    expect(sync.changes(next.cursor).files).toEqual([]);
  });
});

describe("SqlFileStore migration", () => {
  it("adds versions to a table created before versioning without losing rows", () => {
    const sql = memorySql();
    sql.exec("CREATE TABLE files (path TEXT PRIMARY KEY, content TEXT NOT NULL, updated_at INTEGER NOT NULL)");
    sql.exec("INSERT INTO files (path, content, updated_at) VALUES ('old.md', 'old\n', 1)");

    const store = new SqlFileStore(sql);
    store.write("new.md", "new\n");

    expect(store.changesSince(0).map((f) => [f.path, f.version])).toEqual([
      ["old.md", 0],
      ["new.md", 1],
    ]);
    expect(store.changesSince(1)).toEqual([]);
  });
});

describe("push request validation", () => {
  it("accepts well-formed batches and rejects malformed ones", () => {
    const valid = { timeZone: "Europe/Istanbul", ops: [{ opId: "abcdefgh", type: "delete", taskId: "task0001" }] };

    expect(pushRequestSchema.safeParse(valid).success).toBe(true);
    expect(pushRequestSchema.safeParse({ ...valid, timeZone: "Mars/Olympus" }).success).toBe(false);
    expect(pushRequestSchema.safeParse({ ops: [{ opId: "short", type: "delete", taskId: "t" }] }).success).toBe(false);
    expect(
      pushRequestSchema.safeParse({ ops: [{ opId: "abcdefgh", type: "add", text: "x", capturedAt: { date: "2026-02-30", time: "09:00" } }] }).success,
    ).toBe(false);
    expect(pushRequestSchema.safeParse({ ops: [{ opId: "abcdefgh", type: "delete", taskId: "t", extra: 1 }] }).success).toBe(false);
  });
});
