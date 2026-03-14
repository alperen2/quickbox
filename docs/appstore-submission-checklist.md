# App Store Submission Checklist

## Metadata

- App name, subtitle, description, and keywords are finalized.
- Support URL and privacy policy URL are set.
- Primary category and optional secondary category are selected.
- Age rating questionnaire is completed.
- Export compliance answers are completed.

## Build and Validation

- `quickbox-AppStore` archive succeeds in Release.
- `export_appstore.sh` generates a signed `.pkg`.
- App Store Connect validation passes without icon, entitlement, or signing errors.
- App uses App Sandbox with user-selected folder read/write access.
- In-app update UI is not visible in App Store build.

## Screenshots and Review Notes

- Required macOS screenshots are uploaded for all required display sizes.
- Review notes explain:
  - Menu bar behavior and spotlight capture entrypoint.
  - Global shortcut usage.
  - Local-first storage behavior and user-selected folder access.

## Go/No-Go Gates

- CI passed:
  - unit-tests
  - build-appstore
  - ui-smoke
- Privacy manifest (`PrivacyInfo.xcprivacy`) is included.
- Crash diagnostics remain opt-in and do not contain task text.
- Internal smoke test on a clean macOS user account passed.
