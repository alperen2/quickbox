import { oauthProvider } from "./oauth";

export { AccountDirectory } from "./accounts/accountDirectory";
export { InboxStore } from "./store/inboxStore";

export default {
  fetch(request, env, ctx): Promise<Response> {
    return oauthProvider(env).fetch(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;
