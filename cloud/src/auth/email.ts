export interface EmailSender {
  sendSignInCode(to: string, code: string): Promise<void>;
}

export class EmailDeliveryError extends Error {
  override readonly name = "EmailDeliveryError";
}

/** Sends sign-in codes through Resend's HTTP API. */
export class ResendEmailSender implements EmailSender {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  async sendSignInCode(to: string, code: string): Promise<void> {
    const response = await this.fetchImpl("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: this.from,
        to: [to],
        subject: `Your quickbox code: ${code}`,
        text: `Your quickbox sign-in code is ${code}.\n\nIt expires in 10 minutes. If you didn't try to sign in, you can ignore this email.`,
      }),
    });
    if (!response.ok) throw new EmailDeliveryError(`Resend returned ${response.status}`);
  }
}

/** Local development only: prints codes to the `wrangler dev` console instead of emailing them. */
export class ConsoleEmailSender implements EmailSender {
  async sendSignInCode(to: string, code: string): Promise<void> {
    console.log(`[dev] quickbox sign-in code for ${to}: ${code}`);
  }
}

export function emailSender(env: Env): EmailSender | null {
  if (env.RESEND_API_KEY && env.EMAIL_FROM) return new ResendEmailSender(env.RESEND_API_KEY, env.EMAIL_FROM);
  if (env.DEV_LOG_EMAIL_CODES === "true") return new ConsoleEmailSender();
  return null;
}
