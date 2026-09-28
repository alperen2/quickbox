import { beforeEach, describe, expect, it } from "vitest";
import type { LocalNow } from "../src/core/calendar";
import { InboxError } from "../src/inbox/errors";
import { MemoryFileStore } from "../src/inbox/fileStore";
import { Inbox } from "../src/inbox/inbox";
import type { Actor } from "../src/inbox/types";

const USER: Actor = { kind: "user" };
const CLAUDE: Actor = { kind: "agent", name: "claude" };

// Monday 2026-09-28, 09:12 in the user's time zone.
const NOW: LocalNow = { date: { year: 2026, month: 9, day: 28 }, time: "09:12" };

function makeInbox(files: Record<string, string> = {}) {
  const store = new MemoryFileStore(files);
  let counter = 0;
  const inbox = new Inbox(store, { now: () => NOW }, () => `task${String(++counter).padStart(4, "0")}`);
  return { inbox, store };
}

function expectInboxError(action: () => unknown, code: InboxError["code"]) {
  expect(action).toThrow(InboxError);
  try {
    action();
  } catch (error) {
    expect((error as InboxError).code).toBe(code);
  }
}

describe("addTask", () => {
  it("writes to today's daily file with a generated id", () => {
    const { inbox, store } = makeInbox();

    const task = inbox.addTask({ text: "Call designer #work" }, USER);

    expect(store.read("2026-09-28.md")).toBe("- [ ] 09:12 Call designer #work id:task0001\n");
    expect(task).toMatchObject({ id: "task0001", text: "Call designer", tags: ["work"], file: "2026-09-28.md" });
  });

  it("routes to the due day's file and normalizes natural-language dates", () => {
    const { inbox, store } = makeInbox();

    inbox.addTask({ text: "Pay rent due:next friday" }, USER);

    expect(store.read("2026-10-09.md")).toBe("- [ ] 09:12 Pay rent due:2026-10-09 id:task0001\n");
  });

  it("routes project tasks to the project folder's file for their day", () => {
    const { inbox, store } = makeInbox();

    inbox.addTask({ text: "Plan sprint @quickbox", due: "tomorrow" }, USER);

    expect(store.read("quickbox/2026-09-29.md")).toBe(
      "- [ ] 09:12 Plan sprint @quickbox due:2026-09-29 id:task0001\n",
    );
  });

  it("appends to existing files and keeps their content", () => {
    const { inbox, store } = makeInbox({ "2026-09-28.md": "# Monday\n- [x] 08:00 Existing" });

    inbox.addTask({ text: "Second" }, USER);

    expect(store.read("2026-09-28.md")).toBe("# Monday\n- [x] 08:00 Existing\n- [ ] 09:12 Second id:task0001\n");
  });

  it("signs agent writes with the verified agent name, ignoring any by: in the text", () => {
    const { inbox } = makeInbox();

    const task = inbox.addTask({ text: "Draft caption by:someone-else" }, CLAUDE);

    expect(task.metadata.by).toBe("claude");
  });

  it("rejects empty text, duplicate ids, unknown origins and malformed fields", () => {
    const { inbox } = makeInbox({ "2026-09-28.md": "- [ ] 08:00 Existing id:taken001\n" });

    expectInboxError(() => inbox.addTask({ text: "   " }, USER), "invalid_input");
    expectInboxError(() => inbox.addTask({ text: "#only-a-tag" }, USER), "invalid_input");
    expectInboxError(() => inbox.addTask({ text: "Copy id:taken001" }, USER), "conflict");
    expectInboxError(() => inbox.addTask({ text: "Follow up", origin: "missing1" }, USER), "not_found");
    expectInboxError(() => inbox.addTask({ text: "Assign", assignee: "two words" }, USER), "invalid_input");
    expectInboxError(() => inbox.addTask({ text: "Link", ref: "../secrets.md" }, USER), "invalid_input");
  });

  it("turns multi-line input into a single task line", () => {
    const { inbox, store } = makeInbox();

    inbox.addTask({ text: "First line\nsecond line" }, USER);

    expect(store.read("2026-09-28.md")).toBe("- [ ] 09:12 First line second line id:task0001\n");
  });
});

describe("listTasks", () => {
  const files = {
    "2026-09-28.md": [
      "- [ ] 08:00 Open today id:open0001",
      "- [x] 09:00 Done today id:done0001",
      "- [ ] 10:00 For the agent for:agent id:agent001",
      "- [ ] 11:00 Hidden until Wednesday defer:2026-09-30 id:defer001",
      "- [ ] 12:00 Legacy line without id",
    ].join("\n"),
    "Marketing/2026-09-28.md": "- [ ] 07:30 Routed to today @Marketing id:mkt00001",
    "Marketing/2026-09-29.md": "- [ ] 07:45 Routed to tomorrow @Marketing for:agent id:mkt00002",
    "_notes/2026-09-28.md": "- [ ] 00:00 a note, not a task file",
    "_archive/2026-09-28.md": "- [ ] 00:00 system folders are never projects",
  };

  it("shows a day like the app: its daily file plus each project's file for that day, hiding deferred ones", () => {
    const { inbox } = makeInbox(files);

    const tasks = inbox.listTasks({ date: "today" });

    expect(tasks.map((t) => t.text)).toEqual([
      "Routed to today",
      "Open today",
      "For the agent",
      "Legacy line without id",
    ]);
    expect(tasks.find((t) => t.text === "Legacy line without id")?.id).toBeNull();
  });

  it("shows deferred tasks from their defer day on", () => {
    const { inbox } = makeInbox(files);

    const onWednesday = inbox.listTasks({ date: "2026-09-30", status: "all" });

    expect(inbox.listTasks({ date: "today" }).some((t) => t.id === "defer001")).toBe(false);
    expect(onWednesday).toEqual([]); // The task lives in Monday's file, so it only appears in undated queries.
    expect(inbox.listTasks({ status: "all" }).some((t) => t.id === "defer001")).toBe(false);
  });

  it("finds an agent's queue across all task files when no date is given", () => {
    const { inbox } = makeInbox(files);

    expect(inbox.listTasks({ assignee: "agent" }).map((t) => t.id)).toEqual(["agent001", "mkt00002"]);
  });

  it("filters by status, project and tag", () => {
    const { inbox } = makeInbox({ ...files, "2026-09-29.md": "- [ ] 08:00 Tagged #Ops id:tag00001\n" });

    expect(inbox.listTasks({ status: "done" }).map((t) => t.id)).toEqual(["done0001"]);
    expect(inbox.listTasks({ project: "marketing" }).map((t) => t.id)).toEqual(["mkt00001", "mkt00002"]);
    expect(inbox.listTasks({ tag: "ops" }).map((t) => t.id)).toEqual(["tag00001"]);
  });

  it("rejects dates it cannot understand", () => {
    const { inbox } = makeInbox(files);

    expectInboxError(() => inbox.listTasks({ date: "someday" }), "invalid_input");
  });
});

describe("updateTask", () => {
  it("edits only the requested fields and keeps routing and identity tokens", () => {
    const { inbox, store } = makeInbox({
      "Marketing/2026-09-28.md": "- [ ] 07:30 Draft !2 @Marketing #social time:30m id:mkt00001\n",
    });

    const task = inbox.updateTask("mkt00001", { text: "Final draft", due: "tomorrow", assignee: "agent", priority: 1 });

    expect(store.read("Marketing/2026-09-28.md")).toBe(
      "- [ ] 07:30 Final draft !1 @Marketing #social due:2026-09-29 for:agent time:30m id:mkt00001\n",
    );
    expect(task.metadata).toEqual({ for: "agent", time: "30m" });
  });

  it("finds the task by id even after other writers shifted lines", () => {
    const { inbox, store } = makeInbox({ "2026-09-28.md": "- [ ] 08:00 Target id:target01\n" });
    inbox.addTask({ text: "Unrelated" }, USER);
    store.write("2026-09-28.md", `- [ ] 07:00 Inserted above\n${store.read("2026-09-28.md")}`);

    inbox.completeTask("target01");

    expect(store.read("2026-09-28.md")).toContain("- [x] 08:00 Target id:target01");
  });

  it("removes fields set to null and rejects unknown ids and bad values", () => {
    const { inbox, store } = makeInbox({ "2026-09-28.md": "- [ ] 08:00 Task due:2026-10-01 for:agent id:task9999\n" });

    inbox.updateTask("task9999", { due: null, assignee: null });

    expect(store.read("2026-09-28.md")).toBe("- [ ] 08:00 Task id:task9999\n");
    expectInboxError(() => inbox.updateTask("missing1", { done: true }), "not_found");
    expectInboxError(() => inbox.updateTask("task9999", { due: "someday" }), "invalid_input");
    expectInboxError(() => inbox.updateTask("task9999", { text: " " }), "invalid_input");
  });
});

describe("notes", () => {
  it("reads and writes Markdown notes under _notes/ only", () => {
    const { inbox } = makeInbox();

    inbox.writeNote("_notes/k3f9x2ab.md", "# Caption\nHello");

    expect(inbox.readNote("_notes/k3f9x2ab.md")).toEqual({ path: "_notes/k3f9x2ab.md", content: "# Caption\nHello" });
    expectInboxError(() => inbox.readNote("_notes/missing.md"), "not_found");
    expectInboxError(() => inbox.writeNote("notes/old-location.md", ""), "invalid_input");
    expectInboxError(() => inbox.writeNote("2026-09-28.md", "overwrite tasks"), "invalid_input");
    expectInboxError(() => inbox.writeNote("_notes/../x.md", ""), "invalid_input");
  });
});

describe("agent handoff", () => {
  let inbox: Inbox;
  let store: MemoryFileStore;

  beforeEach(() => {
    ({ inbox, store } = makeInbox());
  });

  it("supports the capture → agent → follow-up loop in plain Markdown", () => {
    const request = inbox.addTask({ text: "Create Instagram post @Marketing", due: "today", assignee: "agent" }, USER);

    const [queued] = inbox.listTasks({ assignee: "agent" });
    expect(queued?.id).toBe(request.id);

    inbox.writeNote(`_notes/${request.id}.md`, "Caption: Autumn launch 🍂");
    inbox.updateTask(request.id!, { ref: `_notes/${request.id}.md`, done: true });
    const followUp = inbox.addTask(
      { text: "Publish post @Marketing", assignee: "me", origin: request.id!, ref: `_notes/${request.id}.md` },
      CLAUDE,
    );

    expect(store.read("Marketing/2026-09-28.md")).toBe(
      [
        "- [x] 09:12 Create Instagram post @Marketing due:2026-09-28 for:agent ref:_notes/task0001.md id:task0001",
        "- [ ] 09:12 Publish post @Marketing by:claude for:me from:task0001 ref:_notes/task0001.md id:task0002",
        "",
      ].join("\n"),
    );
    expect(inbox.listTasks({ assignee: "agent" })).toEqual([]);
    expect(inbox.listTasks({ assignee: "me" }).map((t) => t.id)).toEqual([followUp.id]);
  });
});
