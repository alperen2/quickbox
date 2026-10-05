import { PRODUCT_NAME } from "../brand";

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
    // Wrapped so it is never called as a method: Workers throws "Illegal invocation" when
    // `fetch` runs with `this` set to anything but the global scope.
    private readonly fetchImpl: typeof fetch = (input, init) => fetch(input, init),
  ) {}

  async sendSignInCode(to: string, code: string): Promise<void> {
    const response = await this.fetchImpl("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: this.from,
        to: [to],
        subject: `Your ${PRODUCT_NAME} code: ${code}`,
        text: `Your ${PRODUCT_NAME} sign-in code is ${code}.\n\nIt expires in 10 minutes. If you didn't try to sign in, you can ignore this email.`,
      }),
    });
    if (!response.ok) {
      // Resend explains rejections (unverified domain, key scope) in `message`; it never echoes the key.
      const detail = await response
        .json()
        .then((body) => (body as { message?: unknown }).message)
        .catch(() => undefined);
      throw new EmailDeliveryError(`Resend returned ${response.status}${typeof detail === "string" ? `: ${detail}` : ""}`);
    }
  }
}

/** Local development only: prints codes to the `wrangler dev` console instead of emailing them. */
export class ConsoleEmailSender implements EmailSender {
  async sendSignInCode(to: string, code: string): Promise<void> {
    console.log(`[dev] ${PRODUCT_NAME} sign-in code for ${to}: ${code}`);
  }
}

export function emailSender(env: Env): EmailSender | null {
  if (env.RESEND_API_KEY && env.EMAIL_FROM) return new ResendEmailSender(env.RESEND_API_KEY, env.EMAIL_FROM);
  if (env.DEV_LOG_EMAIL_CODES === "true") return new ConsoleEmailSender();
  return null;
}
