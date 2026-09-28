import { DatabaseSync } from "node:sqlite";
import type { Sql, SqlValue } from "../src/store/sql";

/** An in-memory SQLite database behind the `Sql` interface, standing in for Durable Object storage. */
export function memorySql(): Sql {
  const db = new DatabaseSync(":memory:");
  return {
    exec<T extends Record<string, SqlValue>>(query: string, ...bindings: SqlValue[]) {
      const statement = db.prepare(query);
      const rows = statement.columns().length > 0 ? statement.all(...(bindings as never[])) : (statement.run(...(bindings as never[])), []);
      return { toArray: () => rows as T[] };
    },
  };
}
