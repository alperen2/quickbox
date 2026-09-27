export type InboxErrorCode = "invalid_input" | "not_found" | "conflict";

/** An expected failure caused by the request (bad input, unknown id), safe to show to the caller. */
export class InboxError extends Error {
  constructor(
    readonly code: InboxErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "InboxError";
  }
}
