import { McpServer, type CallToolResult } from "@modelcontextprotocol/server";
import * as z from "zod";
import type { InboxApi, InboxResult } from "../inbox/api";
import type { Actor } from "../inbox/types";

export const SERVER_INSTRUCTIONS = `quickbox is the user's inbox of Markdown tasks and notes, shared by the user and their AI agents.

How to work with it:
1. Find your work with list_tasks for="agent". Tasks meant for the user carry for="me".
2. Do the task. Put longer output (drafts, research, copy) in a note: write_note at notes/<task id>.md.
3. Close the loop: complete_task (or update_task with ref=<note path> and done=true). If the user has to do something next (review, approve, publish, send, pay), add_task with for="me", from=<original task id> and ref=<note path>.

Rules:
- Never take irreversible or external actions for the user (publishing, sending, paying, deleting) unless the task explicitly asks you to. Hand them back as a for="me" task instead.
- Refer to tasks by their 8-character id. Tasks with id null are legacy lines and cannot be changed through these tools.
- Task text syntax: !1-!3 priority, @Project, #tag, due:<YYYY-MM-DD or phrases like tomorrow, next friday, in 3 days>.
- Do not store secrets or credentials in tasks or notes.`;

const taskId = z.string().describe("The task's 8-character id, e.g. k3f9x2ab.");
const notePath = z.string().describe("Path of a note, e.g. notes/k3f9x2ab.md.");
const assignee = z.string().describe('Who should act: "me" (the user), "agent", or a specific agent name.');
const dueDate = z.string().describe("YYYY-MM-DD or a phrase such as today, tomorrow, next friday, in 3 days.");

/**
 * Builds the MCP server for one request. `actor` comes from the verified credentials,
 * never from tool input, so an agent cannot write on someone else's behalf.
 */
export function createQuickboxServer(inbox: InboxApi, actor: Actor): McpServer {
  const server = new McpServer(
    { name: "quickbox", version: "0.1.0" },
    { instructions: SERVER_INSTRUCTIONS },
  );

  server.registerTool(
    "list_tasks",
    {
      title: "List tasks",
      description:
        "List tasks. Without a date it searches every task file (use for=\"agent\" to get your queue); with a date it shows that day like the quickbox app does. Defaults to open tasks.",
      inputSchema: z.object({
        date: dueDate.optional(),
        for: assignee.optional(),
        status: z.enum(["open", "done", "all"]).optional(),
        project: z.string().optional(),
        tag: z.string().optional(),
      }),
      annotations: { readOnlyHint: true },
    },
    async ({ date, for: forWhom, status, project, tag }) =>
      toToolResult(await inbox.listTasks({ date, assignee: forWhom, status, project, tag })),
  );

  server.registerTool(
    "add_task",
    {
      title: "Add task",
      description:
        'Add a task. `text` uses quickbox syntax (e.g. "Publish post @Marketing #social !2"). Use for="me" to hand work back to the user, with from=<id of the task it follows> and ref=<note path>.',
      inputSchema: z.object({
        text: z.string().describe("Task description, optionally with !priority, @Project, #tags."),
        due: dueDate.optional(),
        for: assignee.optional(),
        from: taskId.optional().describe("Id of the task this one follows up on."),
        ref: notePath.optional().describe("A related note, e.g. the draft this task is about."),
      }),
    },
    async ({ text, due, for: forWhom, from, ref }) =>
      toToolResult(await inbox.addTask({ text, due, assignee: forWhom, origin: from, ref }, actor)),
  );

  server.registerTool(
    "update_task",
    {
      title: "Update task",
      description: "Change a task. Only the fields you pass change; pass null to clear due, priority, for or ref.",
      inputSchema: z.object({
        id: taskId,
        text: z.string().optional(),
        due: dueDate.nullable().optional(),
        priority: z.union([z.literal(1), z.literal(2), z.literal(3)]).nullable().optional(),
        for: assignee.nullable().optional(),
        ref: notePath.nullable().optional(),
        done: z.boolean().optional(),
      }),
    },
    async ({ id, text, due, priority, for: forWhom, ref, done }) =>
      toToolResult(await inbox.updateTask(id, { text, due, priority, assignee: forWhom, ref, done })),
  );

  server.registerTool(
    "complete_task",
    {
      title: "Complete task",
      description: "Mark a task as done.",
      inputSchema: z.object({ id: taskId }),
      annotations: { idempotentHint: true },
    },
    async ({ id }) => toToolResult(await inbox.completeTask(id)),
  );

  server.registerTool(
    "read_note",
    {
      title: "Read note",
      description: "Read a Markdown note, e.g. the one a task links with ref.",
      inputSchema: z.object({ path: notePath }),
      annotations: { readOnlyHint: true },
    },
    async ({ path }) => toToolResult(await inbox.readNote(path)),
  );

  server.registerTool(
    "write_note",
    {
      title: "Write note",
      description: "Create or replace a Markdown note under notes/. Use notes/<task id>.md for a task's output.",
      inputSchema: z.object({
        path: notePath,
        content: z.string().describe("Full Markdown content; replaces the existing note."),
      }),
      annotations: { idempotentHint: true },
    },
    async ({ path, content }) => toToolResult(await inbox.writeNote(path, content)),
  );

  return server;
}

function toToolResult(result: InboxResult<unknown>): CallToolResult {
  if (!result.ok) return { isError: true, content: [{ type: "text", text: result.error.message }] };
  return { content: [{ type: "text", text: JSON.stringify(result.value) }] };
}
