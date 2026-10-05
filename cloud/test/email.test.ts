import { describe, expect, it } from "vitest";
import { EmailDeliveryError, ResendEmailSender } from "../src/auth/email";

describe("ResendEmailSender", () => {
  it("reports Resend's reason when it rejects a send", async () => {
    const reject: typeof fetch = async () =>
      new Response(JSON.stringify({ statusCode: 403, message: "The example.com domain is not verified." }), { status: 403 });
    const sender = new ResendEmailSender("re_test", "Pigeon <signin@example.com>", reject);

    const error = await sender.sendSignInCode("ada@example.com", "123456").catch((e: unknown) => e);

    expect(error).toBeInstanceOf(EmailDeliveryError);
    expect((error as Error).message).toBe("Resend returned 403: The example.com domain is not verified.");
  });

  it("still fails clearly when the body is not JSON", async () => {
    const reject: typeof fetch = async () => new Response("bad gateway", { status: 502 });
    const sender = new ResendEmailSender("re_test", "Pigeon <signin@example.com>", reject);

    await expect(sender.sendSignInCode("ada@example.com", "123456")).rejects.toThrow("Resend returned 502");
  });
});
