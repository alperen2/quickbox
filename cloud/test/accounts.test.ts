import { describe, expect, it } from "vitest";
import { Accounts, reviewAccount } from "../src/accounts/accounts";
import { memorySql } from "./sqlite";

function makeAccounts() {
  let now = Date.UTC(2026, 8, 28, 9, 0);
  const accounts = new Accounts(memorySql(), () => now);
  return { accounts, advance: (ms: number) => (now += ms) };
}

function requestCode(accounts: Accounts, email: string): string {
  const result = accounts.requestEmailCode(email);
  if (!result.ok) throw new Error(`expected a code, got ${result.reason}`);
  return result.code;
}

describe("email codes", () => {
  it("signs in with a six-digit code and returns the same user next time", () => {
    const { accounts, advance } = makeAccounts();

    const code = requestCode(accounts, " Ada@Example.com ");
    const first = accounts.verifyEmailCode("ada@example.com", code);
    advance(61_000);
    const second = accounts.verifyEmailCode("ada@example.com", requestCode(accounts, "ada@example.com"));

    expect(code).toMatch(/^\d{6}$/);
    expect(first.ok && second.ok && first.userId === second.userId).toBe(true);
  });

  it("uses each code once", () => {
    const { accounts } = makeAccounts();
    const code = requestCode(accounts, "ada@example.com");

    expect(accounts.verifyEmailCode("ada@example.com", code).ok).toBe(true);
    expect(accounts.verifyEmailCode("ada@example.com", code)).toEqual({ ok: false, reason: "expired" });
  });

  it("expires codes after ten minutes", () => {
    const { accounts, advance } = makeAccounts();
    const code = requestCode(accounts, "ada@example.com");

    advance(10 * 60 * 1000 + 1);

    expect(accounts.verifyEmailCode("ada@example.com", code)).toEqual({ ok: false, reason: "expired" });
  });

  it("locks a code after five wrong attempts", () => {
    const { accounts } = makeAccounts();
    const code = requestCode(accounts, "ada@example.com");
    const wrong = code === "000000" ? "111111" : "000000";

    const results = Array.from({ length: 5 }, () => accounts.verifyEmailCode("ada@example.com", wrong));

    expect(results.slice(0, 4).every((r) => !r.ok && r.reason === "invalid_code")).toBe(true);
    expect(results[4]).toEqual({ ok: false, reason: "too_many_attempts" });
    expect(accounts.verifyEmailCode("ada@example.com", code)).toEqual({ ok: false, reason: "too_many_attempts" });
  });

  it("throttles sends per address", () => {
    const { accounts, advance } = makeAccounts();
    requestCode(accounts, "ada@example.com");

    expect(accounts.requestEmailCode("ada@example.com")).toEqual({ ok: false, reason: "rate_limited", retryAfterSeconds: 60 });

    for (let send = 2; send <= 5; send += 1) {
      advance(61_000);
      requestCode(accounts, "ada@example.com");
    }
    advance(61_000);
    const limited = accounts.requestEmailCode("ada@example.com");
    expect(limited.ok === false && limited.reason === "rate_limited").toBe(true);

    advance(60 * 60 * 1000);
    expect(accounts.requestEmailCode("ada@example.com").ok).toBe(true);
  });

  it("rejects malformed addresses and codes for unknown addresses", () => {
    const { accounts } = makeAccounts();

    expect(accounts.requestEmailCode("not-an-email")).toEqual({ ok: false, reason: "invalid_email" });
    expect(accounts.verifyEmailCode("nobody@example.com", "123456")).toEqual({ ok: false, reason: "invalid_code" });
  });
});

describe("Sign in with Apple", () => {
  it("returns the same user for the same Apple subject", () => {
    const { accounts } = makeAccounts();

    const first = accounts.signInWithApple({ subject: "apple-1", email: "ada@example.com", emailVerified: true });
    const second = accounts.signInWithApple({ subject: "apple-1", email: null, emailVerified: false });

    expect(second).toBe(first);
  });

  it("links Apple and email sign-ins that share a verified address", () => {
    const { accounts } = makeAccounts();
    const viaEmail = accounts.verifyEmailCode("ada@example.com", requestCode(accounts, "ada@example.com"));

    const viaApple = accounts.signInWithApple({ subject: "apple-1", email: "Ada@example.com", emailVerified: true });

    expect(viaEmail.ok && viaEmail.userId).toBe(viaApple);
  });

  it("does not link on an unverified email", () => {
    const { accounts } = makeAccounts();
    const viaEmail = accounts.verifyEmailCode("ada@example.com", requestCode(accounts, "ada@example.com"));

    const viaApple = accounts.signInWithApple({ subject: "apple-2", email: "ada@example.com", emailVerified: false });

    expect(viaEmail.ok && viaEmail.userId).not.toBe(viaApple);
  });
});

describe("account deletion", () => {
  it("forgets the user and their identities, so the same address starts fresh", () => {
    const { accounts, advance } = makeAccounts();
    const first = accounts.verifyEmailCode("ada@example.com", requestCode(accounts, "ada@example.com"));
    const appleUser = accounts.signInWithApple({ subject: "apple-1", email: "ada@example.com", emailVerified: true });
    if (!first.ok) throw new Error("sign-in failed");

    accounts.deleteUser(first.userId);
    advance(61_000);
    const again = accounts.verifyEmailCode("ada@example.com", requestCode(accounts, "ada@example.com"));

    expect(appleUser).toBe(first.userId);
    expect(accounts.email(first.userId)).toBeNull();
    expect(again.ok && again.userId).not.toBe(first.userId);
    expect(accounts.signInWithApple({ subject: "apple-1", email: null, emailVerified: false })).not.toBe(first.userId);
  });
});

describe("App Review account", () => {
  const review = reviewAccount("Review@Example.com", "246810")!;

  function makeReviewAccounts() {
    return new Accounts(memorySql(), () => Date.UTC(2026, 8, 28, 9, 0), review);
  }

  it("signs in with the fixed code and sends no email", () => {
    const accounts = makeReviewAccounts();

    const request = accounts.requestEmailCode("review@example.com");

    expect(request).toEqual({ ok: true, code: "246810", deliver: false });
    expect(accounts.verifyEmailCode("review@example.com", "246810").ok).toBe(true);
  });

  it("keeps the attempt limit on the fixed code", () => {
    const accounts = makeReviewAccounts();
    accounts.requestEmailCode("review@example.com");

    for (let attempt = 0; attempt < 5; attempt++) accounts.verifyEmailCode("review@example.com", "000000");

    expect(accounts.verifyEmailCode("review@example.com", "246810")).toEqual({ ok: false, reason: "too_many_attempts" });
  });

  it("leaves other addresses on random, delivered codes", () => {
    const result = makeReviewAccounts().requestEmailCode("ada@example.com");

    expect(result.ok && result.deliver).toBe(true);
  });

  it("is off unless both values are set and the code has six digits", () => {
    expect(reviewAccount("review@example.com", undefined)).toBeNull();
    expect(reviewAccount(undefined, "246810")).toBeNull();
    expect(reviewAccount("review@example.com", "review")).toBeNull();
  });
});
