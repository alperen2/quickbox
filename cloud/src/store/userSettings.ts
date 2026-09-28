import { isValidTimeZone } from "../core/calendar";
import type { Sql } from "./sql";

/** Per-user preferences stored next to the user's files. */
export class UserSettings {
  constructor(private readonly sql: Sql) {
    sql.exec("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  }

  timeZone(): string | null {
    const value = this.sql.exec<{ value: string }>("SELECT value FROM settings WHERE key = 'time_zone'").toArray()[0]?.value;
    return value && isValidTimeZone(value) ? value : null;
  }

  setTimeZone(timeZone: string): void {
    this.sql.exec(
      "INSERT INTO settings (key, value) VALUES ('time_zone', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      timeZone,
    );
  }
}
