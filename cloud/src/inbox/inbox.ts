import { compareDates, formatISODate, type LocalDate, type LocalNow } from "../core/calendar";
import { resolveDueDate } from "../core/dueDate";
import { HandoffKey } from "../core/handoff";
import { generateTaskId, isValidTaskId } from "../core/taskId";
import {
  fieldsOf,
  formatTaskLine,
  parseTaskLine,
  parseTaskLines,
  toSingleLine,
  type TaskLine,
  type TaskLineFields,
} from "../core/taskLine";
import { InboxError } from "./errors";
import { joinLines, splitLines, type FileStore } from "./fileStore";
import type { Actor, NewTask, Note, Task, TaskPatch, TaskQuery } from "./types";

export interface Clock {
  /** Current day and time in the user's time zone. */
  now(): LocalNow;
}

const TOKEN_VALUE_PATTERN = /^[A-Za-z0-9_-]+$/;
/**
 * Storage layout, shared with the Mac app (`StorageLayout.swift`):
 *   <day>.md              inbox tasks for that day
 *   <Project>/<day>.md    project tasks for that day
 *   _notes/<name>.md      free-form notes (agent output)
 * Folders starting with "_" are system folders and never projects.
 */
export const NOTES_FOLDER = "_notes";
const NOTE_PATH_PATTERN = /^_notes\/[A-Za-z0-9_-]+(\/[A-Za-z0-9_-]+)*\.md$/;
const PROJECT_FOLDER_PATTERN = /^[A-Za-z0-9-][A-Za-z0-9_-]*$/;
const MAX_NOTE_BYTES = 256 * 1024;

interface LocatedTask {
  path: string;
  lines: string[];
  line: TaskLine;
}

/**
 * One user's inbox: dated Markdown task files at the root and in project folders, plus
 * free-form notes under `_notes/`. Mirrors the app's routing and editing rules so files
 * written here read the same in the Mac app.
 */
export class Inbox {
  constructor(
    private readonly files: FileStore,
    private readonly clock: Clock,
    private readonly newTaskId: () => string = () => generateTaskId(),
  ) {}

  listTasks(query: TaskQuery = {}): Task[] {
    const today = this.clock.now().date;
    const day = query.date === undefined ? null : this.resolveDay(query.date, today);
    const visibleFrom = day ?? today;
    const status = query.status ?? "open";

    return this.tasksFor(day)
      .filter(({ line }) => !isHiddenByDefer(line, visibleFrom, today))
      .filter(({ line }) => status === "all" || line.completed === (status === "done"))
      .filter(({ line }) => matches(line.metadata[HandoffKey.assignee], query.assignee))
      .filter(({ line }) => matches(line.project, query.project))
      .filter(({ line }) => query.tag === undefined || line.tags.some((tag) => matches(tag, query.tag)))
      .sort((a, b) => (day ? 0 : a.path.localeCompare(b.path)) || a.line.time.localeCompare(b.line.time))
      .map(({ path, line }) => toTask(path, line));
  }

  addTask(input: NewTask, actor: Actor): Task {
    const now = this.clock.now();
    const parsed = parseTaskLine(`- [ ] 00:00 ${composeDraft(input)}`);
    if (!parsed || parsed.text === "") {
      throw new InboxError("invalid_input", "Task text is empty. Put the task description before any tokens.");
    }

    const taskId = parsed.taskId ?? this.unusedTaskId();
    if (this.find(taskId)) throw new InboxError("conflict", `A task with id "${taskId}" already exists.`);

    const metadata = { ...parsed.metadata };
    const origin = metadata[HandoffKey.origin];
    if (origin !== undefined && !this.find(origin)) {
      throw new InboxError("not_found", `from:${origin} does not match any task id.`);
    }
    if (actor.kind === "agent") metadata[HandoffKey.author] = actor.name;

    const resolvedDue = parsed.due === null ? null : resolveDueDate(parsed.due, now.date);
    const targetDay = formatISODate(resolvedDue ?? now.date);
    const path = parsed.project === null ? `${targetDay}.md` : `${parsed.project}/${targetDay}.md`;

    const line = formatTaskLine({
      ...fieldsOf(parsed),
      time: now.time,
      due: resolvedDue ? formatISODate(resolvedDue) : parsed.due,
      metadata,
      // The file's day routes the task; the legacy `date:` tag is no longer written.
      routeDate: null,
      taskId,
    });

    this.files.write(path, joinLines([...splitLines(this.files.read(path)), line]));
    return toTask(path, this.require(taskId).line);
  }

  updateTask(taskId: string, patch: TaskPatch): Task {
    const located = this.require(taskId);
    const fields = fieldsOf(located.line);
    applyPatch(fields, patch, this.clock.now().date);

    located.lines[located.line.lineIndex] = formatTaskLine(fields);
    this.files.write(located.path, joinLines(located.lines));
    return toTask(located.path, this.require(taskId).line);
  }

  completeTask(taskId: string): Task {
    return this.updateTask(taskId, { done: true });
  }

  readNote(path: string): Note {
    const content = this.files.read(validNotePath(path));
    if (content === null) throw new InboxError("not_found", `No note at ${path}.`);
    return { path, content };
  }

  writeNote(path: string, content: string): Note {
    if (new TextEncoder().encode(content).byteLength > MAX_NOTE_BYTES) {
      throw new InboxError("invalid_input", `Notes are limited to ${MAX_NOTE_BYTES / 1024} KB.`);
    }
    this.files.write(validNotePath(path), content);
    return { path, content };
  }

  /** A day shows its inbox file and the same-named file in every project folder, like the app. */
  private tasksFor(day: LocalDate | null): LocatedTask[] {
    const dayFileName = day ? `${formatISODate(day)}.md` : null;

    return this.taskFiles()
      .filter((path) => dayFileName === null || path.split("/").pop() === dayFileName)
      .flatMap((path) => {
        const lines = splitLines(this.files.read(path));
        return parseTaskLines(lines, path).map((line) => ({ path, lines, line }));
      });
  }

  private find(taskId: string): LocatedTask | null {
    for (const path of this.taskFiles()) {
      const lines = splitLines(this.files.read(path));
      const line = parseTaskLines(lines, path).find((candidate) => candidate.taskId === taskId);
      if (line) return { path, lines, line };
    }
    return null;
  }

  private require(taskId: string): LocatedTask {
    const located = this.find(taskId);
    if (!located) throw new InboxError("not_found", `No task with id "${taskId}".`);
    return located;
  }

  private unusedTaskId(): string {
    let taskId = this.newTaskId();
    while (this.find(taskId)) taskId = this.newTaskId();
    return taskId;
  }

  /** Task files: `.md` files at the root and directly inside project folders. */
  private taskFiles(): string[] {
    return this.files.list().filter(isTaskFilePath).sort();
  }

  private resolveDay(value: string, today: LocalDate): LocalDate {
    const day = resolveDueDate(value, today);
    if (!day) throw new InboxError("invalid_input", `Unrecognized date "${value}". Use YYYY-MM-DD or a phrase like "tomorrow".`);
    return day;
  }
}

/** Like the app, a task stays hidden until its `defer:` day. */
function isHiddenByDefer(line: TaskLine, visibleFrom: LocalDate, today: LocalDate): boolean {
  const deferValue = line.metadata.defer;
  if (deferValue === undefined) return false;
  const deferDay = resolveDueDate(deferValue, today);
  return deferDay !== null && compareDates(visibleFrom, deferDay) < 0;
}

/** Appends structured fields as tokens after the free text, so they win over tokens typed in `text`. */
function composeDraft(input: NewTask): string {
  const tokens = [toSingleLine(input.text).trim()];
  if (input.due !== undefined) tokens.push(`due:${input.due}`);
  if (input.assignee !== undefined) tokens.push(`${HandoffKey.assignee}:${tokenValue(input.assignee, "for")}`);
  if (input.origin !== undefined) tokens.push(`${HandoffKey.origin}:${taskIdValue(input.origin)}`);
  if (input.ref !== undefined) tokens.push(`${HandoffKey.reference}:${validNotePath(input.ref)}`);
  return tokens.join(" ");
}

function applyPatch(fields: TaskLineFields, patch: TaskPatch, today: LocalDate): void {
  if (patch.text !== undefined) {
    const text = toSingleLine(patch.text).trim();
    if (!text) throw new InboxError("invalid_input", "Task text cannot be empty.");
    fields.text = text;
  }
  if (patch.due !== undefined) {
    if (patch.due === null) {
      fields.due = null;
    } else {
      const due = resolveDueDate(patch.due, today);
      if (!due) throw new InboxError("invalid_input", `Unrecognized due date "${patch.due}".`);
      fields.due = formatISODate(due);
    }
  }
  if (patch.priority !== undefined) fields.priority = patch.priority;
  if (patch.assignee !== undefined) {
    setToken(fields, HandoffKey.assignee, patch.assignee === null ? null : tokenValue(patch.assignee, "for"));
  }
  if (patch.ref !== undefined) {
    setToken(fields, HandoffKey.reference, patch.ref === null ? null : validNotePath(patch.ref));
  }
  if (patch.done !== undefined) fields.completed = patch.done;
}

function setToken(fields: TaskLineFields, key: string, value: string | null): void {
  if (value === null) delete fields.metadata[key];
  else fields.metadata[key] = value;
}

function tokenValue(value: string, key: string): string {
  if (!TOKEN_VALUE_PATTERN.test(value)) {
    throw new InboxError("invalid_input", `${key}: must be a single word of letters, digits, "-" or "_".`);
  }
  return value;
}

function taskIdValue(value: string): string {
  if (!isValidTaskId(value)) throw new InboxError("invalid_input", `"${value}" is not a valid task id.`);
  return value;
}

function validNotePath(path: string): string {
  if (!NOTE_PATH_PATTERN.test(path)) {
    throw new InboxError("invalid_input", `Note paths look like ${NOTES_FOLDER}/<name>.md (letters, digits, "-", "_").`);
  }
  return path;
}

function isTaskFilePath(path: string): boolean {
  if (!path.endsWith(".md")) return false;
  const parts = path.split("/");
  if (parts.length === 1) return true;
  return parts.length === 2 && PROJECT_FOLDER_PATTERN.test(parts[0]!);
}

function matches(value: string | null | undefined, expected: string | undefined): boolean {
  return expected === undefined || value?.toLowerCase() === expected.toLowerCase();
}

function toTask(path: string, line: TaskLine): Task {
  return {
    id: line.taskId,
    text: line.text,
    done: line.completed,
    time: line.time,
    file: path,
    project: line.project,
    tags: line.tags,
    priority: line.priority,
    due: line.due,
    metadata: line.metadata,
  };
}
