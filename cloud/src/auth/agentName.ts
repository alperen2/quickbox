/** Turns an OAuth client's display name into a `by:` token value, e.g. "Claude Desktop" → "claude-desktop". */
export function agentName(displayName: string): string {
  const slug = displayName
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || "agent";
}
