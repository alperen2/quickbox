import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { BRAND_MARK_SVG } from "../src/auth/brandMark";
import { messagePage } from "../src/auth/pages";

describe("sign-in pages", () => {
  it("inline the logo mark exactly as brand/pigeon-mark.svg", () => {
    const source = readFileSync(fileURLToPath(new URL("../../brand/pigeon-mark.svg", import.meta.url)), "utf8");

    expect(BRAND_MARK_SVG).toBe(source);
  });

  it("show the mark and product name on every page", () => {
    const html = messagePage("Title", "Message");

    expect(html).toContain('<div class="brand"><svg');
    expect(html).toContain("<span>Pigeon</span>");
  });
});
