import type { FileStore } from "../inbox/fileStore";
import type { Sql } from "./sql";

export interface FileVersion {
  path: string;
  content: string;
  version: number;
}

/**
 * `FileStore` on a Durable Object's SQLite storage. One row per Markdown file keeps files the
 * source of truth. Every write stamps the file with the next value of a store-wide counter, so
 * clients can ask for "everything that changed after version N".
 */
export class SqlFileStore implements FileStore {
  constructor(private readonly sql: Sql) {
    sql.exec(`CREATE TABLE IF NOT EXISTS files (
      path TEXT PRIMARY KEY,
      content TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )`);
    // Added after the first deployment; existing rows start at version 0 (older than any cursor > 0).
    const columns = sql.exec<{ name: string }>("PRAGMA table_info(files)").toArray();
    if (!columns.some((column) => column.name === "version")) {
      sql.exec("ALTER TABLE files ADD COLUMN version INTEGER NOT NULL DEFAULT 0");
    }
    sql.exec("CREATE INDEX IF NOT EXISTS files_by_version ON files(version)");
    sql.exec("CREATE TABLE IF NOT EXISTS counters (name TEXT PRIMARY KEY, value INTEGER NOT NULL)");
  }

  read(path: string): string | null {
    const row = this.sql.exec<{ content: string }>("SELECT content FROM files WHERE path = ?", path).toArray()[0];
    return row?.content ?? null;
  }

  write(path: string, content: string): void {
    this.sql.exec(
      `INSERT INTO files (path, content, updated_at, version) VALUES (?, ?, ?, ?)
       ON CONFLICT(path) DO UPDATE SET
         content = excluded.content, updated_at = excluded.updated_at, version = excluded.version`,
      path,
      content,
      Date.now(),
      this.nextVersion(),
    );
  }

  list(): string[] {
    return this.sql
      .exec<{ path: string }>("SELECT path FROM files ORDER BY path")
      .toArray()
      .map((row) => row.path);
  }

  /** Files written after `cursor`, oldest first. Cursor 0 means everything, including pre-versioning rows. */
  changesSince(cursor: number): FileVersion[] {
    return this.sql
      .exec<{ path: string; content: string; version: number }>(
        "SELECT path, content, version FROM files WHERE ? = 0 OR version > ? ORDER BY version, path",
        cursor,
        cursor,
      )
      .toArray();
  }

  /** The latest version handed out; a client that has seen it is fully up to date. */
  currentVersion(): number {
    return this.sql.exec<{ value: number }>("SELECT value FROM counters WHERE name = 'files'").toArray()[0]?.value ?? 0;
  }

  private nextVersion(): number {
    this.sql.exec(
      `INSERT INTO counters (name, value) VALUES ('files', 1)
       ON CONFLICT(name) DO UPDATE SET value = value + 1`,
    );
    return this.currentVersion();
  }
}
