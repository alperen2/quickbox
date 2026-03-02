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
- use the circled calendar button next to quick capture to open the larger calendar view with quick day/week/month jumps

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
- `due:date` — Sets a deadline. Supports natural phrases like `due:next friday`, `due:end of month`, `due:in 2 weeks`, plus shorthands like `tdy`, `tmr`, `nw`, and `eow`.
- `defer:date` or `start:date` — Hides the task from your inbox until the specified date arrives (examples: `defer:next monday`, `start:in 3 days`).
- `time:duration` or `dur:duration` — Sets a planned duration (e.g., `15m`, `2h`, `1d`) and updates the right-side planned time range.
- `remind:duration` or `alarm:duration` — Sets a notification alert.

Natural language date parsing is intentionally limited to `due:`, `defer:`, and `start:` values to keep behavior deterministic and distraction-free.

### Interactive Features
When typing `@`, `#`, or keywords like `due:` and `time:`, Quickbox provides an **interactive autocomplete menu**.
* **Smart Previews:** The menu shows exactly what time or date a shorthand or phrase (like `eow` or `next friday`) resolves to.
* **Clickable Pills:** You can click on the generated metadata pills in your task list to quickly edit values or remove them without manual text editing.

## Menubar utility

Use menu actions for:

- Open Today File
- Open Inbox Folder
- Check for Updates
- Settings
