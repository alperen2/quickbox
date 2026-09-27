/**
 * Storage for the user's Markdown files. Synchronous on purpose: the Durable Object's
 * SQLite API is synchronous, so each inbox operation runs atomically without locks.
 */
export interface FileStore {
  read(path: string): string | null;
  write(path: string, content: string): void;
  list(): string[];
}

export class MemoryFileStore implements FileStore {
  private readonly files = new Map<string, string>();

  constructor(initial: Record<string, string> = {}) {
    for (const [path, content] of Object.entries(initial)) this.files.set(path, content);
  }

  read(path: string): string | null {
    return this.files.get(path) ?? null;
  }

  write(path: string, content: string): void {
    this.files.set(path, content);
  }

  list(): string[] {
    return [...this.files.keys()];
  }
}

/** Splits file content into lines, dropping the trailing empty line(s) like the app does. */
export function splitLines(content: string | null): string[] {
  if (!content) return [];
  const lines = content.split("\n");
  while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

export function joinLines(lines: readonly string[]): string {
  return lines.length === 0 ? "" : `${lines.join("\n")}\n`;
}
