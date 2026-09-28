# Privacy

quickbox is local-first.

## Stored data

- tasks in local markdown files
- app preferences in UserDefaults

## quickbox Cloud (optional)

quickbox Cloud is off until you connect it in Settings. When it is connected:

- **What is stored:** your email address, and a copy of your task files and notes. This data lets AI agents you connect (such as Claude) and your other devices use your inbox.
- **Where:** on Cloudflare, in a storage unit dedicated to your account. Sign-in codes are sent by email through Resend.
- **Who can access it:** only apps and agents you approve on the sign-in page. You can see and disconnect them at any time in Settings → quickbox Cloud → Connected apps.
- **Deleting your data:** Settings → quickbox Cloud → Delete account… disconnects every app and agent, then permanently deletes the cloud copy of your tasks and notes and your account. Files in your local folder are not touched.
- **Disconnecting a Mac:** this stops syncing and revokes that Mac's access. Cloud data stays until you delete the account.

## Crash diagnostics

Disabled by default.

When enabled, diagnostics include technical metadata only (version, OS, operation context). Task text content is excluded.

## App Store disclosure summary

- quickbox does not track users across apps or websites.
- quickbox does not collect task content for analytics or advertising.
- With quickbox Cloud connected, your email address and task content are stored to provide sync and agent access. They are linked to your account, never used for tracking, and deleted with the account.
- Crash diagnostics are optional and controlled by the user.
- Privacy manifest is provided via `quickbox/PrivacyInfo.xcprivacy`.
