import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/** Reads a file from the repository-level `fixtures/` folder shared with the Swift app. */
export function readFixture<T>(name: string): T {
  const url = new URL(`../../fixtures/${name}`, import.meta.url);
  return JSON.parse(readFileSync(fileURLToPath(url), "utf8")) as T;
}
