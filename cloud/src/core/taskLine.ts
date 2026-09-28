import { isValidTaskId, TASK_ID_KEY } from "./taskId";

/**
 * The quickbox Markdown task line format:
 *
 *     - [ ] HH:mm text !1 @Project #tag due:YYYY-MM-DD key:value date:YYYY-MM-DD id:xxxxxxxx
 *
 * `parseTaskLines` is a port of `InboxParser.swift` and must pass `fixtures/task-lines.json`.
 * `formatTaskLine` mirrors how the app writes lines (token order included).
 */

export interface TaskLine {
  /** Position-independent when the line has an `id:`; otherwise index + raw content. */
  readonly itemId: string;
  readonly lineIndex: number;
  readonly rawLine: string;
  readonly completed: boolean;
  readonly time: string;
  readonly text: string;
  readonly tags: string[];
  readonly priority: number | null;
  readonly project: string | null;
  readonly due: string | null;
  /** Other `key:value` tokens. Never contains `id`, `due` or the hidden `date` routing tag. */
  readonly metadata: Record<string, string>;
  readonly taskId: string | null;
}

/** Fields that make up a line when writing it back. */
export interface TaskLineFields {
  completed: boolean;
  time: string;
  text: string;
  tags: string[];
  priority: number | null;
  project: string | null;
  due: string | null;
  metadata: Record<string, string>;
  /** Hidden routing tag for tasks stored in project files. */
  routeDate: string | null;
  taskId: string | null;
}

const TASK_PATTERN = /^- \[(?<done>[ xX])\] (?<time>\d{2}:\d{2}) (?<text>.+)$/;
const TAG_PATTERN = /#([a-zA-Z0-9_-]+)/g;
const PRIORITY_PATTERN = /!([1-3])/g;
const PROJECT_PATTERN = /@([a-zA-Z0-9_-]+)/g;
const ROUTE_DATE_PATTERN = /date:([0-9]{4}-[0-9]{2}-[0-9]{2})/;
const METADATA_KEY_PATTERN = /^[a-zA-Z0-9_-]+$/;
const NEXT_METADATA_PATTERN = /^[a-zA-Z0-9_-]+:/;
const COMPACT_RELATIVE_DATE_PATTERN = /^in\d+(day|days|d|week|weeks|w|month|months|m)$/;
const NUMERIC_PATTERN = /^\d+$/;
const DATE_METADATA_KEYS = new Set(["due", "defer", "start"]);
const DATE_PHRASE_TOKENS = new Set([
  "today", "tdy", "tomorrow", "tmr", "next", "in", "week", "weekend", "weeks",
  "end", "of", "day", "days", "month", "months", "year",
  "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
]);

export function parseTaskLines(lines: readonly string[], sourceId: string): TaskLine[] {
  const seenTaskIds = new Set<string>();
  const items: TaskLine[] = [];

  lines.forEach((line, index) => {
    const match = TASK_PATTERN.exec(line);
    if (!match?.groups) return;

    const rawText = match.groups.text!;
    const tags = [...rawText.matchAll(TAG_PATTERN)].map((m) => m[1]!);
    const priorityMatch = rawText.match(/!([1-3])/);
    const projectMatch = rawText.match(/@([a-zA-Z0-9_-]+)/);

    const extraction = extractMetadataTokens(rawText);
    let due: string | null = null;
    let taskId: string | null = null;
    const metadata: Record<string, string> = {};
    for (const [key, value] of Object.entries(extraction.values)) {
      if (key === "due") due = value;
      else if (key === TASK_ID_KEY) taskId = isValidTaskId(value) ? value : null;
      else if (key !== "date") metadata[key] = value;
    }

    const text = extraction.remainingText
      .replace(TAG_PATTERN, "")
      .replace(PRIORITY_PATTERN, "")
      .replace(PROJECT_PATTERN, "")
      .replace(/^[ \t]+|[ \t]+$/g, "");

    // A duplicated `id:` (e.g. a copy-pasted line) must not alias two items.
    if (taskId !== null) {
      if (seenTaskIds.has(taskId)) taskId = null;
      else seenTaskIds.add(taskId);
    }

    items.push({
      itemId: taskId !== null ? `${sourceId}#${TASK_ID_KEY}:${taskId}` : `${sourceId}#${index}#${line}`,
      lineIndex: index,
      rawLine: line,
      completed: match.groups.done !== " ",
      time: match.groups.time!,
      text,
      tags,
      priority: priorityMatch ? Number(priorityMatch[1]) : null,
      project: projectMatch ? projectMatch[1]! : null,
      due,
      metadata,
      taskId,
    });
  });

  return items;
}

/** Parses a single line on its own, e.g. to rebuild it. Unlike in a file, a duplicated id is kept. */
export function parseTaskLine(line: string): TaskLine | null {
  return parseTaskLines([line], "line")[0] ?? null;
}

/** The hidden `date:` routing tag of a line, which the parser does not expose. */
export function routeDateOf(rawLine: string): string | null {
  return ROUTE_DATE_PATTERN.exec(rawLine)?.[1] ?? null;
}

export function fieldsOf(line: TaskLine): TaskLineFields {
  return {
    completed: line.completed,
    time: line.time,
    text: line.text,
    tags: [...line.tags],
    priority: line.priority,
    project: line.project,
    due: line.due,
    metadata: { ...line.metadata },
    routeDate: routeDateOf(line.rawLine),
    taskId: line.taskId,
  };
}

/** Writes a line with the app's token order: text, priority, project, tags, due, metadata (sorted), date, id. */
export function formatTaskLine(fields: TaskLineFields): string {
  const components = [toSingleLine(fields.text)];
  if (fields.priority !== null) components.push(`!${fields.priority}`);
  if (fields.project !== null) components.push(`@${fields.project}`);
  for (const tag of fields.tags) components.push(`#${tag}`);
  if (fields.due !== null) components.push(`due:${fields.due}`);
  for (const key of Object.keys(fields.metadata).sort()) components.push(`${key}:${fields.metadata[key]}`);
  if (fields.routeDate !== null) components.push(`date:${fields.routeDate}`);
  if (fields.taskId !== null) components.push(`${TASK_ID_KEY}:${fields.taskId}`);
  return `- [${fields.completed ? "x" : " "}] ${fields.time} ${components.join(" ")}`;
}

export function toSingleLine(text: string): string {
  return text.replace(/\r\n|\n|\r/g, " ");
}

function extractMetadataTokens(text: string): { values: Record<string, string>; remainingText: string } {
  const tokens = text.split(/\s+/).filter(Boolean);
  const values: Record<string, string> = {};
  const consumed = new Set<number>();

  let index = 0;
  while (index < tokens.length) {
    const token = tokens[index]!;
    const colonIndex = token.indexOf(":");
    if (colonIndex === -1) {
      index += 1;
      continue;
    }

    const key = token.slice(0, colonIndex).toLowerCase();
    if (!METADATA_KEY_PATTERN.test(key) || key === "http" || key === "https") {
      index += 1;
      continue;
    }

    const inlineValue = token.slice(colonIndex + 1);

    if (DATE_METADATA_KEYS.has(key)) {
      const phrase: string[] = inlineValue ? [inlineValue] : [];
      let lookahead = index + 1;
      while (lookahead < tokens.length && continuesDatePhrase(tokens[lookahead]!)) {
        phrase.push(tokens[lookahead]!);
        lookahead += 1;
      }

      const joined = phrase.join(" ").trim();
      if (joined) {
        values[key] = joined;
        for (let consumedIndex = index; consumedIndex < lookahead; consumedIndex += 1) consumed.add(consumedIndex);
        index = lookahead;
        continue;
      }
    } else if (inlineValue) {
      values[key] = inlineValue;
      consumed.add(index);
    }

    index += 1;
  }

  const remainingText = tokens.filter((_, tokenIndex) => !consumed.has(tokenIndex)).join(" ");
  return { values, remainingText };
}

function continuesDatePhrase(token: string): boolean {
  const normalized = token.toLowerCase();
  if (normalized.startsWith("#") || normalized.startsWith("@") || normalized.startsWith("!")) return false;
  if (normalized.startsWith("http://") || normalized.startsWith("https://")) return false;
  if (NEXT_METADATA_PATTERN.test(normalized)) return false;
  return (
    DATE_PHRASE_TOKENS.has(normalized) ||
    NUMERIC_PATTERN.test(normalized) ||
    COMPACT_RELATIVE_DATE_PATTERN.test(normalized)
  );
}
