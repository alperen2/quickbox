/**
 * The subset of Durable Object `SqlStorage` the stores use. Declared structurally so the same
 * SQL runs against `node:sqlite` in tests.
 */
export type SqlValue = string | number | null | ArrayBuffer;

export interface Sql {
  exec<T extends Record<string, SqlValue>>(query: string, ...bindings: SqlValue[]): { toArray(): T[] };
}
