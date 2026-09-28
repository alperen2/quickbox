# Connect an AI agent

Pigeon Cloud lets the AI assistants you already use work from the same inbox as you. Agents connect through [MCP](https://modelcontextprotocol.io), so there is nothing to install, and they use your own Claude or ChatGPT subscription.

Pigeon Cloud is optional. Without it, Pigeon only writes to your local folder.

## Server address

```
https://api.usepigeon.cc/mcp
```

When you add it, a Pigeon page opens. Sign in with Apple or an email code, then allow the app. You can see and disconnect every connected app in **Settings → Pigeon Cloud → Connected apps**.

## Claude

1. On claude.ai, open **Customize → Connectors** and add a custom connector.
2. Paste the server address and click **Add**. Leave the advanced OAuth fields empty.
3. In a chat, turn the connector on from the **+** menu under **Connectors**.

Connectors you add on claude.ai also work in Claude Desktop and the mobile apps. On Team and Enterprise plans, an owner adds the connector under **Organization settings → Connectors** first.

## ChatGPT and other MCP clients

Any client that supports remote MCP servers with OAuth can connect with the same address. In ChatGPT this needs **Developer mode**, which is not available on every plan. Turn it on in settings, then create an app for a remote MCP server with the address above.

## How agents and you share work

Tasks are ordinary Pigeon lines, with a few extra keys:

| Key | Meaning |
| --- | --- |
| `for:agent` | Work for an agent. `for:me` is work handed back to you. |
| `by:` | Who wrote the task. Pigeon sets it from the connected app's name. |
| `from:` | The task this one follows up on. |
| `ref:` | A note with the agent's longer output, e.g. `_notes/k3f9x2ab.md`. |

A typical loop:

1. You capture `Draft the launch post for:agent @Marketing`.
2. You ask your assistant to check its Pigeon tasks. It writes the draft to a note and completes the task.
3. It adds `Review launch post for:me` with a `ref:` to the note, so the next step shows up in your inbox.

Agents are told not to publish, send, pay or delete on your behalf unless the task explicitly asks them to. They hand those steps back to you instead.
