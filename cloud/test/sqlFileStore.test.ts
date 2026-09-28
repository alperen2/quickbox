import { describe, expect, it } from "vitest";
import { SqlFileStore } from "../src/store/sqlFileStore";
import { memorySql } from "./sqlite";

describe("SqlFileStore", () => {
  it("stores one row per file and overwrites on write", () => {
    const sql = memorySql();
    const store = new SqlFileStore(sql);

    store.write("2026-09-28.md", "- [ ] 08:00 First\n");
    store.write("notes/a.md", "note");
    store.write("2026-09-28.md", "- [x] 08:00 First\n");

    expect(store.read("2026-09-28.md")).toBe("- [x] 08:00 First\n");
    expect(store.read("missing.md")).toBeNull();
    expect(store.list()).toEqual(["2026-09-28.md", "notes/a.md"]);
    // Re-opening on the same storage keeps the data (the table is created only once).
    expect(new SqlFileStore(sql).read("notes/a.md")).toBe("note");
  });
});
