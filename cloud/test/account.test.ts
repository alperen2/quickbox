import type { GrantSummary } from "@cloudflare/workers-oauth-provider";
import { describe, expect, it } from "vitest";
import { handleAccountRequest, type AccountDeps } from "../src/account/api";

function grant(id: string, clientId: string, clientName: string, createdAt: number): GrantSummary {
  return { id, clientId, userId: "user-1", scope: ["inbox"], metadata: { clientName }, createdAt } as GrantSummary;
}

function makeDeps() {
  const calls: string[] = [];
  const grants = [grant("g-app", "app-client", "quickbox", 100), grant("g-claude", "dcr-1", "Claude", 200)];
  const deps: AccountDeps = {
    grants: {
      // Two pages, to exercise pagination.
      async listUserGrants(_userId, options) {
        return options?.cursor ? { items: grants.slice(1) } : { items: grants.slice(0, 1), cursor: "next" };
      },
      async revokeGrant(grantId) {
        calls.push(`revoke:${grantId}`);
        grants.splice(grants.findIndex((g) => g.id === grantId), 1);
      },
    },
    directory: {
      async accountEmail() {
        return "ada@example.com";
      },
      async deleteUser(userId) {
        calls.push(`deleteUser:${userId}`);
      },
    },
    inbox: {
      async deleteAllData() {
        calls.push("deleteInbox");
      },
    },
    firstPartyClientId: "app-client",
  };
  return { deps, calls, grants };
}

const principal = { userId: "user-1", grantId: "g-app" };
const request = (method: string, path: string, body?: unknown) =>
  new Request(`https://quickbox.test${path}`, { method, body: body === undefined ? undefined : JSON.stringify(body) });

describe("account API", () => {
  it("lists connected apps newest first, marking this device and quickbox apps", async () => {
    const { deps } = makeDeps();

    const response = await handleAccountRequest(request("GET", "/mcp/account"), principal, deps);

    expect(await response.json()).toEqual({
      email: "ada@example.com",
      apps: [
        { grantId: "g-claude", name: "Claude", connectedAt: 200_000, isQuickboxApp: false, isThisDevice: false },
        { grantId: "g-app", name: "quickbox", connectedAt: 100_000, isQuickboxApp: true, isThisDevice: true },
      ],
    });
  });

  it("disconnects one app, but only one that belongs to the user", async () => {
    const { deps, calls } = makeDeps();

    const revoked = await handleAccountRequest(request("DELETE", "/mcp/account/apps/g-claude"), principal, deps);
    const foreign = await handleAccountRequest(request("DELETE", "/mcp/account/apps/someone-elses"), principal, deps);

    expect(revoked.status).toBe(204);
    expect(foreign.status).toBe(404);
    expect(calls).toEqual(["revoke:g-claude"]);
  });

  it("requires explicit confirmation to delete the account", async () => {
    const { deps, calls } = makeDeps();

    const response = await handleAccountRequest(request("POST", "/mcp/account/delete", { confirm: "yes" }), principal, deps);

    expect(response.status).toBe(400);
    expect(calls).toEqual([]);
  });

  it("deletes the account: all access first, then data, then the account itself", async () => {
    const { deps, calls } = makeDeps();

    const response = await handleAccountRequest(request("POST", "/mcp/account/delete", { confirm: "DELETE" }), principal, deps);

    expect(response.status).toBe(204);
    expect(calls).toEqual(["revoke:g-app", "revoke:g-claude", "deleteInbox", "deleteUser:user-1"]);
  });
});
