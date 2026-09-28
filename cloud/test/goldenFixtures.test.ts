import { describe, expect, it } from "vitest";
import { formatISODate, parseISODate } from "../src/core/calendar";
import { resolveDueDate } from "../src/core/dueDate";
import { parseTaskLines } from "../src/core/taskLine";
import { readFixture } from "./fixtures";

interface ExpectedItem {
  lineIndex: number;
  completed: boolean;
  time: string;
  text: string;
  tags: string[];
  priority: number | null;
  project: string | null;
  due: string | null;
  metadata: Record<string, string>;
  taskID: string | null;
}

interface TaskLineFixtures {
  cases: { name: string; lines: string[]; expected: ExpectedItem[] }[];
}

interface DueDateFixtures {
  groups: { reference: string; cases: { input: string; expected: string | null }[] }[];
}

describe("fixtures/task-lines.json", () => {
  const { cases } = readFixture<TaskLineFixtures>("task-lines.json");

  it.each(cases.map((c) => [c.name, c] as const))("%s", (_, fixture) => {
    const actual = parseTaskLines(fixture.lines, "fixture.md").map(
      (item): ExpectedItem => ({
        lineIndex: item.lineIndex,
        completed: item.completed,
        time: item.time,
        text: item.text,
        tags: item.tags,
        priority: item.priority,
        project: item.project,
        due: item.due,
        metadata: item.metadata,
        taskID: item.taskId,
      }),
    );
    expect(actual).toEqual(fixture.expected);
  });
});

describe("fixtures/due-dates.json", () => {
  const { groups } = readFixture<DueDateFixtures>("due-dates.json");
  const cases = groups.flatMap((group) => group.cases.map((c) => [group.reference, c.input, c.expected] as const));

  it.each(cases)("%s + %j", (reference, input, expected) => {
    const today = parseISODate(reference)!;
    const resolved = resolveDueDate(input, today);
    expect(resolved ? formatISODate(resolved) : null).toBe(expected);
  });
});
