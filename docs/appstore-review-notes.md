# App Store Review Notes Template

Use this text (adapt as needed) in the App Review notes section.

Pigeon is a local-first macOS menu bar capture app.

- The app runs in the menu bar and opens a spotlight-style capture panel with a global shortcut.
- Captured entries are written to user-selected local markdown files.
- On first setup, the user chooses a folder via the system folder picker.
- The app does not require an account for its core features and does not download executable code.
- App Store build does not include in-app update flow. Updates are handled by the Mac App Store.

## Pigeon Cloud (optional sign-in)

Add this when the build includes Pigeon Cloud. Replace the placeholders with the values set as the server's `APP_REVIEW_EMAIL` and `APP_REVIEW_CODE` secrets. Put the code only in App Store Connect, never in this repository.

- Pigeon Cloud is optional. It syncs the user's tasks and lets AI assistants the user connects (for example Claude) read and add tasks.
- To try it: Settings → Pigeon Cloud → Connect → Continue with email.
  - Email: `<review email>`
  - Code: `<six-digit review code>` (no email is sent to this address)
- Account deletion: Settings → Pigeon Cloud → Delete account… permanently deletes the account and its cloud data.

