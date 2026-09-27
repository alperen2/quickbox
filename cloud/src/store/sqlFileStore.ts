import type { FileStore } from "../inbox/fileStore";

/** `FileStore` on a Durable Object's SQLite storage. One row per Markdown file keeps files the source of truth. */
export class SqlFileStore implements FileStore {
  constructor(private readonly sql: SqlStorage) {
    sql.exec(`CREATE TABLE IF NOT EXISTS files (
      path TEXT PRIMARY KEY,
      content TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )`);
  }

  read(path: string): string | null {
    const row = this.sql.exec<{ content: string }>("SELECT content FROM files WHERE path = ?", path).toArray()[0];
    return row?.content ?? null;
  }

  write(path: string, content: string): void {
    this.sql.exec(
      `INSERT INTO files (path, content, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(path) DO UPDATE SET content = excluded.content, updated_at = excluded.updated_at`,
      path,
      content,
      Date.now(),
    );
  }

  list(): string[] {
    return this.sql
      .exec<{ path: string }>("SELECT path FROM files ORDER BY path")
      .toArray()
      .map((row) => row.path);
  }
}
