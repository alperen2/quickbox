import { DurableObject } from "cloudflare:workers";
import { Accounts, type AppleIdentity } from "./accounts";

/**
 * The global user directory. A single instance keeps email-code attempts and account
 * linking strongly consistent; per-user data lives in each user's `InboxStore`.
 */
export class AccountDirectory extends DurableObject<Env> {
  private readonly accounts: Accounts;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.accounts = new Accounts(ctx.storage.sql);
  }

  async requestEmailCode(email: string) {
    return this.accounts.requestEmailCode(email);
  }

  async verifyEmailCode(email: string, code: string) {
    return this.accounts.verifyEmailCode(email, code);
  }

  async signInWithApple(identity: AppleIdentity) {
    return this.accounts.signInWithApple(identity);
  }
}

export function accountDirectory(env: Env) {
  return env.ACCOUNTS.get(env.ACCOUNTS.idFromName("global"));
}
