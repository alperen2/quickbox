import {
  addDays,
  addMonths,
  lenientDate,
  parseISODate,
  weekday,
  type LocalDate,
  type Weekday,
} from "./calendar";

/**
 * Resolves natural-language `due:` / `defer:` / `start:` values to a calendar day.
 * Port of `DueDateResolver.swift`; both are checked against `fixtures/due-dates.json`.
 */
export function resolveDueDate(input: string, today: LocalDate): LocalDate | null {
  const value = input.toLowerCase().split(/\s+/).filter(Boolean).join(" ");

  // 1. Shorthands
  switch (value) {
    case "today":
    case "tdy":
      return today;
    case "tomorrow":
    case "tmr":
      return addDays(today, 1);
    case "nextweek":
    case "next-week":
    case "nw":
      return addDays(today, 7);
    case "nextweekend":
    case "next-weekend":
    case "next weekend":
      return nextWeekday(7, today, false);
    case "endofweek":
    case "eow":
    case "end of week":
      return nextWeekday(6, today, true);
    case "endofmonth":
    case "eom":
    case "end of month":
      return addDays(addMonths({ ...today, day: 1 }, 1), -1);
    case "endofyear":
    case "eoy":
    case "end of year":
      return { year: today.year, month: 12, day: 31 };
  }

  // 2. next <weekday>
  const nextWeekdayMatch = /^next ([a-z]+)$/.exec(value);
  if (nextWeekdayMatch) {
    const target = WEEKDAYS[nextWeekdayMatch[1]!];
    if (target) return addDays(nextWeekday(target, today, false), 7);
  }

  // 3. <weekday>
  const weekdayTarget = WEEKDAYS[value];
  if (weekdayTarget) return nextWeekday(weekdayTarget, today, false);

  // 4. in <n> days|weeks|months
  const relative = /^in (\d+) (day|days|week|weeks|month|months)$/.exec(value);
  if (relative) return addUnit(today, Number(relative[1]), relative[2]!);

  // 5. in<n>d | in<n>w | in<n>m
  const compact = /^in(\d+)(day|days|d|week|weeks|w|month|months|m)$/.exec(value);
  if (compact) return addUnit(today, Number(compact[1]), compact[2]!);

  // 6. Bare day of month: next occurrence (this month if still ahead, otherwise next month)
  const bareDay = /^(\d{1,2})$/.exec(value);
  if (bareDay) {
    const day = Number(bareDay[1]);
    if (day >= 1 && day <= 31) {
      return lenientDate(today.year, day <= today.day ? today.month + 1 : today.month, day);
    }
  }

  // 7. jan15 / 15jan
  const monthDay = /^([a-z]{3})(\d{1,2})$/.exec(value);
  if (monthDay && MONTHS[monthDay[1]!]) return nextMonthDay(MONTHS[monthDay[1]!]!, Number(monthDay[2]), today);
  const dayMonth = /^(\d{1,2})([a-z]{3})$/.exec(value);
  if (dayMonth && MONTHS[dayMonth[2]!]) return nextMonthDay(MONTHS[dayMonth[2]!]!, Number(dayMonth[1]), today);

  // 8. YYYY-MM-DD
  return parseISODate(value);
}

const WEEKDAYS: Record<string, Weekday> = {
  sunday: 1,
  monday: 2,
  tuesday: 3,
  wednesday: 4,
  thursday: 5,
  friday: 6,
  saturday: 7,
};

const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

function addUnit(date: LocalDate, amount: number, unit: string): LocalDate | null {
  if (unit.startsWith("d")) return addDays(date, amount);
  if (unit.startsWith("w")) return addDays(date, amount * 7);
  if (unit.startsWith("m")) return addMonths(date, amount);
  return null;
}

function nextWeekday(target: Weekday, from: LocalDate, includeToday: boolean): LocalDate {
  let delta = target - weekday(from);
  if (includeToday ? delta < 0 : delta <= 0) delta += 7;
  return addDays(from, delta);
}

function nextMonthDay(month: number, day: number, today: LocalDate): LocalDate {
  const isPast = month < today.month || (month === today.month && day < today.day);
  return lenientDate(isPast ? today.year + 1 : today.year, month, day);
}
