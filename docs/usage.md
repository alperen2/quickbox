# Usage

## Quick capture

1. Press the global shortcut
2. Type thought
3. Press Enter

## Today list

Inside spotlight panel, manage today's items quickly:

- toggle done/undone
- edit
- delete + undo

## Quickbox Syntax

Quickbox uses a powerful, natural language-friendly syntax to organize your thoughts instantly:

### Projects & Context
- `@ProjectName` — Routes the task to a specific project file (e.g., `ProjectName.md`) instead of the daily inbox.

### Priorities
- `!1` — High Priority
- `!2` — Medium Priority
- `!3` — Low Priority

### Tags
- `#tagname` — Adds a tag to the task for easy filtering and organization.

### Dates & Time (Key-Value)
- `due:date` — Sets a deadline. Supports shorthands like `tdy` (today), `tmr` (tomorrow), `nw` (next week), `eow` (end of week), or exact dates like `15jan`.
- `defer:date` veya `start:date` — Hides the task from your inbox until the specified date arrives. Only appears when you need it!
- `time:duration` veya `dur:duration` — Sets a planned duration for the task (e.g., `15m`, `2h`, `1d`). Updates the right-side timestamp to show the planned time range.
- `remind:duration` veya `alarm:duration` — Sets a notification alert.

### Interactive Features
When typing `@`, `#`, or keywords like `due:` and `time:`, Quickbox provides an **interactive autocomplete menu**.
* **Smart Previews:** The menu shows exactly what time or date a shorthand (like `15m` or `eow`) resolves to.
* **Clickable Pills:** You can click on the generated metadata pills in your task list to quickly edit values or remove them without manual text editing.

## Menubar utility

Use menu actions for:

- Open Today File
- Open Inbox Folder
- Check for Updates
- Settings
