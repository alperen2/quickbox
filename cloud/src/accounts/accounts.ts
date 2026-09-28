import { createHash, randomInt, randomUUID, timingSafeEqual } from "node:crypto";
import type { Sql } from "../store/sql";

export const EMAIL_CODE_LENGTH = 6;
const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const RESEND_INTERVAL_MS = 60 * 1000;
const SEND_WINDOW_MS = 60 * 60 * 1000;
const MAX_SENDS_PER_WINDOW = 5;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export type EmailCodeRequest =
  | { ok: true; code: string }
  | { ok: false; reason: "invalid_email" }
  | { ok: false; reason: "rate_limited"; retryAfterSeconds: number };

export type EmailCodeVerification =
  | { ok: true; userId: string }
  | { ok: false; reason: "invalid_code" | "expired" | "too_many_attempts" };

export interface AppleIdentity {
  /** Apple's stable user identifier (`sub`). */
  subject: string;
  email: string | null;
  emailVerified: boolean;
}

/**
 * Users and how they sign in. Hashing and randomness are synchronous (`node:crypto`) so each
 * method runs without awaiting, which keeps it atomic inside the Durable Object.
 *
 * Accounts are linked by verified email: signing in with Apple and with an email code for the
 * same address reaches the same user. Apple's private relay addresses therefore stay separate.
 */
export class Accounts {
  constructor(
    private readonly sql: Sql,
    private readonly now: () => number = Date.now,
  ) {
    sql.exec(`CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE,
      created_at INTEGER NOT NULL
    )`);
    sql.exec(`CREATE TABLE IF NOT EXISTS identities (
      provider TEXT NOT NULL,
      subject TEXT NOT NULL,
      user_id TEXT NOT NULL REFERENCES users(id),
      PRIMARY KEY (provider, subject)
    )`);
    sql.exec(`CREATE TABLE IF NOT EXISTS email_codes (
      email TEXT PRIMARY KEY,
      code_hash TEXT NOT NULL,
      expires_at INTEGER NOT NULL,
      attempts INTEGER NOT NULL,
      sent_at INTEGER NOT NULL,
      window_started_at INTEGER NOT NULL,
      sends_in_window INTEGER NOT NULL
    )`);
  }

  /** Issues a new one-time code for `email`, replacing any earlier one. The caller emails it. */
  requestEmailCode(rawEmail: string): EmailCodeRequest {
    const email = normalizeEmail(rawEmail);
    if (!email) return { ok: false, reason: "invalid_email" };

    const now = this.now();
    const previous = this.sql
      .exec<{ sent_at: number; window_started_at: number; sends_in_window: number }>(
        "SELECT sent_at, window_started_at, sends_in_window FROM email_codes WHERE email = ?",
        email,
      )
      .toArray()[0];

    const windowOpen = previous !== undefined && now - previous.window_started_at < SEND_WINDOW_MS;
    const sendsInWindow = windowOpen ? previous.sends_in_window : 0;
    if (previous && now - previous.sent_at < RESEND_INTERVAL_MS) {
      return { ok: false, reason: "rate_limited", retryAfterSeconds: secondsUntil(previous.sent_at + RESEND_INTERVAL_MS, now) };
    }
    if (windowOpen && sendsInWindow >= MAX_SENDS_PER_WINDOW) {
      return { ok: false, reason: "rate_limited", retryAfterSeconds: secondsUntil(previous.window_started_at + SEND_WINDOW_MS, now) };
    }

    const code = String(randomInt(0, 10 ** EMAIL_CODE_LENGTH)).padStart(EMAIL_CODE_LENGTH, "0");
    this.sql.exec(
      `INSERT INTO email_codes (email, code_hash, expires_at, attempts, sent_at, window_started_at, sends_in_window)
       VALUES (?, ?, ?, 0, ?, ?, ?)
       ON CONFLICT(email) DO UPDATE SET
         code_hash = excluded.code_hash, expires_at = excluded.expires_at, attempts = 0,
         sent_at = excluded.sent_at, window_started_at = excluded.window_started_at,
         sends_in_window = excluded.sends_in_window`,
      email,
      hashCode(email, code),
      now + CODE_TTL_MS,
      now,
      windowOpen ? previous.window_started_at : now,
      sendsInWindow + 1,
    );
    return { ok: true, code };
  }

  /** Checks a code; on success the code is used up and the email's user is returned (created if new). */
  verifyEmailCode(rawEmail: string, rawCode: string): EmailCodeVerification {
    const email = normalizeEmail(rawEmail);
    const code = rawCode.replace(/\s+/g, "");
    const row = email
      ? this.sql
          .exec<{ code_hash: string; expires_at: number; attempts: number }>(
            "SELECT code_hash, expires_at, attempts FROM email_codes WHERE email = ?",
            email,
          )
          .toArray()[0]
      : undefined;
    if (!email || !row) return { ok: false, reason: "invalid_code" };

    if (this.now() > row.expires_at) return { ok: false, reason: "expired" };
    if (row.attempts >= MAX_ATTEMPTS) return { ok: false, reason: "too_many_attempts" };

    if (!constantTimeEqual(row.code_hash, hashCode(email, code))) {
      this.sql.exec("UPDATE email_codes SET attempts = attempts + 1 WHERE email = ?", email);
      return { ok: false, reason: row.attempts + 1 >= MAX_ATTEMPTS ? "too_many_attempts" : "invalid_code" };
    }

    // Burn the code but keep the row so resend throttling still applies.
    this.sql.exec("UPDATE email_codes SET expires_at = 0 WHERE email = ?", email);
    return { ok: true, userId: this.userForIdentity("email", email, email) };
  }

  email(userId: string): string | null {
    return this.sql.exec<{ email: string | null }>("SELECT email FROM users WHERE id = ?", userId).toArray()[0]?.email ?? null;
  }

  /** Forgets the user, their sign-in identities and any pending email code. */
  deleteUser(userId: string): void {
    const email = this.email(userId);
    this.sql.exec("DELETE FROM identities WHERE user_id = ?", userId);
    this.sql.exec("DELETE FROM users WHERE id = ?", userId);
    if (email) this.sql.exec("DELETE FROM email_codes WHERE email = ?", email);
  }

  signInWithApple(identity: AppleIdentity): string {
    const verifiedEmail = identity.emailVerified && identity.email ? normalizeEmail(identity.email) : null;
    return this.userForIdentity("apple", identity.subject, verifiedEmail);
  }

  /** Finds the user for an identity, linking it to an existing user with the same verified email, or creates one. */
  private userForIdentity(provider: string, subject: string, verifiedEmail: string | null): string {
    const linked = this.sql
      .exec<{ user_id: string }>("SELECT user_id FROM identities WHERE provider = ? AND subject = ?", provider, subject)
      .toArray()[0];
    if (linked) return linked.user_id;

    const existing = verifiedEmail
      ? this.sql.exec<{ id: string }>("SELECT id FROM users WHERE email = ?", verifiedEmail).toArray()[0]
      : undefined;
    const userId = existing?.id ?? randomUUID();
    if (!existing) {
      this.sql.exec("INSERT INTO users (id, email, created_at) VALUES (?, ?, ?)", userId, verifiedEmail, this.now());
    }
    this.sql.exec("INSERT INTO identities (provider, subject, user_id) VALUES (?, ?, ?)", provider, subject, userId);
    return userId;
  }
}

export function normalizeEmail(value: string): string | null {
  const email = value.trim().toLowerCase();
  return email.length <= 254 && EMAIL_PATTERN.test(email) ? email : null;
}

function hashCode(email: string, code: string): string {
  return createHash("sha256").update(`${email}:${code}`).digest("hex");
}

function constantTimeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}

function secondsUntil(time: number, now: number): number {
  return Math.max(1, Math.ceil((time - now) / 1000));
}
