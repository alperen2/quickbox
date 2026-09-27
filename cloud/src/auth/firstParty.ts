import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";
import { accountDirectory } from "../accounts/accountDirectory";

/** Where the quickbox apps receive the authorization code (ASWebAuthenticationSession callback). */
export const APP_REDIRECT_URI = "quickbox://oauth/callback";
export const APP_CLIENT_NAME = "quickbox";

let cachedClientId: string | undefined;

/**
 * The quickbox apps' OAuth client. Dynamic registration picks a random id, so the id is created
 * once and recorded in the strongly consistent account directory. Only tokens issued to this
 * client may use the sync API, which writes as the user rather than as an agent.
 */
export async function ensureFirstPartyClientId(env: Env, oauth: OAuthHelpers): Promise<string> {
  const existing = cachedClientId ?? (await accountDirectory(env).firstPartyClientId());
  if (existing && (await oauth.lookupClient(existing))) return (cachedClientId = existing);

  const client = await oauth.createClient({
    clientName: APP_CLIENT_NAME,
    redirectUris: [APP_REDIRECT_URI],
    tokenEndpointAuthMethod: "none",
    grantTypes: ["authorization_code", "refresh_token"],
    responseTypes: ["code"],
  });
  return (cachedClientId = await accountDirectory(env).claimFirstPartyClientId(client.clientId));
}

export async function isFirstPartyClient(env: Env, clientId: string): Promise<boolean> {
  const firstParty = cachedClientId ?? (await accountDirectory(env).firstPartyClientId());
  if (firstParty) cachedClientId = firstParty;
  return firstParty !== null && firstParty === clientId;
}
