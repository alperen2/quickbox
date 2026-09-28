/**
 * Calendar-date arithmetic in the user's time zone.
 *
 * Task files are keyed by local calendar days, so the server works with plain
 * `{ year, month, day }` values instead of instants. The arithmetic mirrors
 * Foundation's `Calendar` (months clamp to the last valid day), which keeps the
 * cloud and the Swift app resolving the same phrases to the same days.
 */

export interface LocalDate {
  readonly year: number;
  /** 1-12 */
  readonly month: number;
  /** 1-31 */
  readonly day: number;
}

/** Sunday = 1 ... Saturday = 7, matching Foundation's `Calendar.component(.weekday, ...)`. */
export type Weekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export interface LocalNow {
  readonly date: LocalDate;
  /** `HH:mm`, 24-hour clock. */
  readonly time: string;
}

const ISO_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Builds a date the way `Calendar.date(from:)` does: out-of-range days/months roll over. */
export function lenientDate(year: number, month: number, day: number): LocalDate {
  return fromUTC(new Date(Date.UTC(year, month - 1, day)));
}

export function parseISODate(value: string): LocalDate | null {
  const match = ISO_DATE_PATTERN.exec(value);
  if (!match) return null;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = lenientDate(year, month, day);
  // Reject impossible dates such as 2026-02-30 instead of rolling them over.
  return date.year === year && date.month === month && date.day === day ? date : null;
}

export function formatISODate(date: LocalDate): string {
  return `${pad(date.year, 4)}-${pad(date.month, 2)}-${pad(date.day, 2)}`;
}

export function addDays(date: LocalDate, days: number): LocalDate {
  return lenientDate(date.year, date.month, date.day + days);
}

/** Adds months and clamps to the target month's last day (Jan 31 + 1 month = Feb 28). */
export function addMonths(date: LocalDate, months: number): LocalDate {
  const firstOfTarget = lenientDate(date.year, date.month + months, 1);
  const lastDay = daysInMonth(firstOfTarget.year, firstOfTarget.month);
  return { ...firstOfTarget, day: Math.min(date.day, lastDay) };
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

export function weekday(date: LocalDate): Weekday {
  return (toUTC(date).getUTCDay() + 1) as Weekday;
}

export function compareDates(a: LocalDate, b: LocalDate): number {
  return formatISODate(a).localeCompare(formatISODate(b));
}

/** The current calendar day and wall-clock time in `timeZone` (an IANA name such as `Europe/Istanbul`). */
export function zonedNow(timeZone: string, now: Date = new Date()): LocalNow {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const part = (type: Intl.DateTimeFormatPartTypes) => Number(parts.find((p) => p.type === type)?.value);

  return {
    date: { year: part("year"), month: part("month"), day: part("day") },
    time: `${pad(part("hour"), 2)}:${pad(part("minute"), 2)}`,
  };
}

export function isValidTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch {
    return false;
  }
}

function toUTC(date: LocalDate): Date {
  return new Date(Date.UTC(date.year, date.month - 1, date.day));
}

function fromUTC(value: Date): LocalDate {
  return { year: value.getUTCFullYear(), month: value.getUTCMonth() + 1, day: value.getUTCDate() };
}

function pad(value: number, length: number): string {
  return String(value).padStart(length, "0");
}
