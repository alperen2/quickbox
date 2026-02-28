# Getting Started

## Requirements

- macOS 14+
- Xcode 16+

## Run locally

```bash
open quickbox.xcodeproj
```

Select `quickbox` scheme and run.

## Run tests

```bash
xcodebuild test -project quickbox.xcodeproj -scheme quickbox -destination 'platform=macOS' -only-testing:quickboxTests
```
