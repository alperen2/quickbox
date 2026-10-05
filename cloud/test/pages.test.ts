import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { BRAND_MARK_SVG } from "../src/auth/brandMark";
import { codeLimitPage, messagePage, waitDescription } from "../src/auth/pages";

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

  it("say plainly when the hourly code limit is reached", () => {
    const html = codeLimitPage("state-1", "ada@example.com", 2040);

    expect(html).toContain("<h1>Too many codes</h1>");
    expect(html).toContain("in about 34 minutes");
    expect(html).not.toContain("Check your email");
  });

  it("describe short and long waits", () => {
    expect(waitDescription(1)).toBe("in 1 second");
    expect(waitDescription(45)).toBe("in 45 seconds");
    expect(waitDescription(2829)).toBe("in about 48 minutes");
  });
});
