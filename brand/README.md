# Pigeon brand

Pigeon is an agentic to-do tracker: you capture a thought in a second, and the AI agents you connect pick up tasks and hand work back. The mark is a **P** whose counter is a pigeon wearing a headset: a messenger that works for you.

## Logo files

| File | Use |
| --- | --- |
| `pigeon-mark.svg` | The P mark alone. Favicon, nav bar, sign-in pages, avatars. |
| `pigeon-wordmark.svg` | The lowercase "pigeon" wordmark. Use it next to or under the mark. |
| `pigeon-logo-original.png` | The original lockup (mark, wordmark, tagline, domain), 364×439. Reference only. |

The SVGs were traced from the original PNG. They work at web sizes. For the app icon and print, export fresh vectors from the design source.

- The pigeon is negative space. On a dark background it takes the background color, so the mark works on light and dark surfaces without a separate version.
- Keep clear space around the mark at least as wide as the P's stem.
- Do not recolor, outline, rotate or add effects to the mark. On busy photos, put it on a white or coral tile.
- Write the product name as **Pigeon** in text. The wordmark's lowercase "pigeon" is artwork only.

## Colors

| Role | Hex | Notes |
| --- | --- | --- |
| Coral (primary) | `#F36175` | The logo color. Large type, illustrations, fills behind dark text. 3.1:1 on white, so never use it for body text on white. |
| Magenta (secondary) | `#F25181` | The headset. Small accents in artwork only. |
| Coral 600 | `#D1425A` | Buttons with white text and the macOS accent in light mode (4.5:1 with white). |
| Coral 700 | `#C53650` | Links and brand text on white (5.2:1). |
| Coral 800 | `#AD193D` | Hover and pressed states on white (7:1). |
| Coral light | `#FF7C8B` | Links on dark backgrounds (7:1 on `#1B1B1F`). |
| Tint | `#FFEDEF` | Soft backgrounds and highlights. |

The darker shades keep the same OKLCH hue (15°) as the logo coral, so they read as the same color instead of drifting to red. In dark mode, coral `#F36175` works as text and as a fill behind dark text (5.5:1 on `#1B1B1F`).

Status colors stay semantic and separate from the brand. In the app, priority `!1` is red, `!2` orange and `!3` blue, and token highlights keep their own colors. Coral is not a priority color.

## Type

- **Wordmark:** custom artwork, use the SVG. Don't set "pigeon" in a font to imitate it.
- **Interface text:** the platform font. That's SF Pro on macOS, the app and the sign-in pages, and Inter on the website (the VitePress default).
- **Tagline:** "Agentic To Do Tracker".

## Voice

Short, plain and calm. Say what happens and what the user does next. Avoid hype.

- Talk about "your agents" and "your inbox". The user stays in charge.
- Agents *pick up* and *hand back* work. They never act on the user's behalf in public (publish, send, pay) unless a task says so.
- UI copy is English. Product names are **Pigeon** and **Pigeon Cloud**.

## Where the brand is applied

| Surface | Source |
| --- | --- |
| Website | `docs/.vitepress/theme/custom.css`, `docs/public/pigeon-mark.svg`, `docs/index.md` |
| Sign-in and consent pages | `cloud/src/auth/pages.ts` and `cloud/src/auth/brandMark.ts` (inlined, `test/pages.test.ts` keeps it in sync) |
| macOS accent color | `quickbox/Assets.xcassets/AccentColor.colorset` |
| Product names | `quickbox/Shared/Brand.swift`, `cloud/src/brand.ts` |

Still open: the app icon, the menu bar icon (a template version of the mark), and the email template.
