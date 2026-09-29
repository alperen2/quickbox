import { DurableObject } from "cloudflare:workers";
import { Accounts, reviewAccount, type AppleIdentity } from "./accounts";

/**
 * The global user directory. A single instance keeps email-code attempts and account
 * linking strongly consistent; per-user data lives in each user's `InboxStore`.
 */
export class AccountDirectory extends DurableObject<Env> {
  private readonly accounts: Accounts;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.accounts = new Accounts(ctx.storage.sql, Date.now, reviewAccount(env.APP_REVIEW_EMAIL, env.APP_REVIEW_CODE));
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  }

  /** The OAuth client id of the quickbox apps, or null before the first one is registered. */
  async firstPartyClientId(): Promise<string | null> {
    return (
      this.ctx.storage.sql
        .exec<{ value: string }>("SELECT value FROM settings WHERE key = 'first_party_client_id'")
        .toArray()[0]?.value ?? null
    );
  }

  /** Records `clientId` unless another request got there first; returns the id that won. */
  async claimFirstPartyClientId(clientId: string): Promise<string> {
    this.ctx.storage.sql.exec(
      "INSERT INTO settings (key, value) VALUES ('first_party_client_id', ?) ON CONFLICT(key) DO NOTHING",
      clientId,
    );
    return (await this.firstPartyClientId())!;
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

  async accountEmail(userId: string) {
    return this.accounts.email(userId);
  }

  async deleteUser(userId: string) {
    this.accounts.deleteUser(userId);
  }
}

export function accountDirectory(env: Env) {
  return env.ACCOUNTS.get(env.ACCOUNTS.idFromName("global"));
}
