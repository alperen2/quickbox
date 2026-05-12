# quickbox Design System

A design system for **quickbox** — a fast, native macOS app for putting files in boxes and getting them out again. quickbox lives in the Mac menu bar and on the desktop; every surface it has to render looks, feels, and behaves exactly like a first-class macOS 26 app.

This design system is how we keep it that way.

---

## Context & provenance

quickbox is a macOS-native product. Rather than invent a parallel visual language, we build on top of the **macOS 26 (Tahoe) design language**. This system is the quickbox-specific layer on top of that: the brand tokens, the product screens, the copy voice.

### Source materials
- **Figma:** *macOS 26 (Community)* — Apple's reference kit mounted as this project's virtual filesystem during authoring. Covers Windows, Buttons, Sidebars, Toolbars, Sheets, Popovers, Menus, Materials (Liquid Glass), and full Desktop examples.
- **Apple Human Interface Guidelines — Designing for macOS** (external reference; not included).
- **SF Pro** + **SF Pro Rounded** (Apple system fonts — substituted here, see *Fonts* below).
- **SF Symbols** (Apple icon font — substituted here, see *Iconography* below).

Assumptions made (flag if wrong):
1. quickbox is a macOS-first native app; the design system is light-mode first with a dark-mode pass.
2. The brand color is a warm system-compatible orange (macOS 26 Orange, `rgb(255, 149, 0)`) — it reads as energetic but doesn't fight the OS chrome. Swap via `--brand` if you want a different accent.
3. There is no marketing website in scope yet — only the Mac app surfaces.

---

## Index

Root files:
- `README.md` — this file (context, content + visual foundations, iconography).
- `SKILL.md` — portable skill definition so this folder drops into Claude Code as `quickbox-design`.
- `colors_and_type.css` — all design tokens: colors, type scale, radii, shadows, materials, spacing.
- `fonts/` — webfont fallbacks for SF Pro family.
- `assets/` — logos, icon sprites, imagery.
- `preview/` — small HTML cards surfacing each token/component for the Design System tab.
- `ui_kits/quickbox-mac/` — the quickbox macOS app UI kit (JSX components + `index.html` demo).

---

## Content fundamentals

quickbox's voice is **direct, calm, and macOS-polite**. We write the way the OS talks to you in the Finder: short, human, never cute.

### Rules
- **Second person, singular.** "Drop files to send them." Never "Let's drop your files!"
- **Sentence case for everything.** Menu items, buttons, titles, notifications — all sentence case (`Send to…`, `New drop box`). *Never* Title Case, *never* ALL CAPS.
- **Verbs do the work.** Buttons are verbs, not nouns: `Send`, `Cancel`, `Open`, `Move to Trash`. Avoid `OK`/`Submit`/`Done` unless the action is genuinely generic.
- **Ellipsis means "a next step is coming".** `Open…` opens a picker. `Open` opens the thing immediately. Use `…` (U+2026), not three dots.
- **Contractions are fine.** "Can't connect" > "Cannot connect."
- **No marketing voice inside the product.** No "Awesome!", "🎉", no exclamation marks except in genuine alerts.
- **No emoji in UI.** SF Symbols only. Emoji may appear in filenames the user brought, but we never introduce them.
- **Numbers are specific.** `3 files` not `a few files`. `2.1 MB` not `About 2 MB`.
- **Errors are honest and recoverable.** State what happened, why, and what to do next, in that order.

### Examples

| Don't | Do |
|---|---|
| Woohoo! Your files are on their way 🚀 | Sending 4 files to Alex. |
| Oops, something went wrong. | Can't connect to iCloud Drive. Check your network and try again. |
| Submit | Send |
| Delete File? | Move "budget.xlsx" to Trash? |
| Welcome Back, User! | |

Empty states lead with the next action, not the empty state: `Drop files here to start a box` — not `No boxes yet.`

---

## Visual foundations

### Palette
We inherit the macOS 26 system color palette wholesale. These are OS-native — using anything else makes the app feel like an Electron port.

- **Labels (text):** `label`, `secondary-label`, `tertiary-label`, `quaternary-label` — all derived from black at 85 / 50 / 25 / 10% alpha. Use labels, never raw black.
- **Fills (backgrounds for controls):** `fill-primary` through `fill-quinary`, derived from black at 10 / 8 / 5 / 3 / 2% alpha. Controls sit on fills; fills sit on window background.
- **Accents (System):** Red `255,56,60` · Orange `255,149,0` · Yellow `255,204,0` · Green `40,205,65` · Mint `0,199,190` · Teal `89,173,196` · Cyan `85,190,240` · Blue `0,122,255` · Indigo `88,86,214` · Purple `175,82,222` · Pink `255,45,85` · Brown `162,132,94` · Gray `142,142,147`.
- **quickbox brand:** `--brand` = Orange `255,149,0`. Used sparingly — the active selection, the primary action in a modal, the menu-bar icon highlight. Never used as a page background.

### Type
- **SF Pro** (Text + Display are unified in SF Pro 17+). Weights in use: Regular (400), Medium (500), Semibold (600), Bold (700), Heavy (800). Heavy only appears at very large sizes (32px+) in empty-state hero copy.
- **SF Pro Rounded** is reserved for playful moments — the onboarding "welcome" and the completion confetti toast. Not used in chrome.
- **Scale** mirrors Apple's text styles: LargeTitle 26 / Title1 22 / Title2 17 / Title3 15 / Headline 13sb / Body 13 / Callout 12 / Subheadline 11 / Footnote 10 / Caption1 10 / Caption2 10b. Body text is 13px — this is the HIG default; it looks tiny on web mockups but correct in the real OS at default scaling.
- **Letter spacing** follows Apple's dynamic tracking — negative tracking on large sizes (-0.4 at 32px) and slightly positive on the smallest (+0.06 at 10px). Tokens encode this.

### Materials (Liquid Glass)
macOS 26's signature surface is **Liquid Glass** — a backdrop-filtered pane that blurs + tints what's behind it. quickbox uses three variants:
- **Glass Thin** — for popovers and menu-bar content. `backdrop-filter: saturate(180%) blur(30px)`, background `rgba(255,255,255,0.72)`, 1px inner top highlight `rgba(255,255,255,0.5)`, outer 1px hairline `rgba(0,0,0,0.12)`.
- **Glass Regular** — for sidebars, sheet headers. Same blur, background `rgba(245,245,245,0.85)`.
- **Glass Thick** — for floating panels that need stronger separation (the menu-bar drop surface). `saturate(200%) blur(40px)`, background `rgba(255,255,255,0.55)`.

All three flip to dark equivalents in dark mode.

### Corners
- Windows: **16px** (standard), **26px** for sheet/utility (Tahoe's softer look).
- Sheets: **16px top corners only** when attached to a titlebar.
- Control buttons: **6px** (standard push button).
- Capsule controls / segmented buttons: **pill** (half-height).
- Menu items / sidebar rows: **6px**.
- Icon tiles (dock / toolbar): **22%** of tile size (a "squircle" approximation).
- Cards (content containers): **10px**.

### Shadows & elevation
Three elevation tiers. Shadows stay tight — macOS prefers thin hairlines + a soft drop, not big diffuse glow.

- **0 — flat** (inline content): none.
- **1 — popover** (menus, tooltips): `0 0 0 0.5px rgba(0,0,0,0.15)` + `0 8px 24px rgba(0,0,0,0.14)`.
- **2 — sheet / alert**: `0 0 0 0.5px rgba(0,0,0,0.15)` + `0 24px 56px rgba(0,0,0,0.28)`.
- **3 — floating window**: `0 0 0 0.5px rgba(0,0,0,0.23)` + `0 16px 48px rgba(0,0,0,0.35)`.

Note the hairline: 0.5px inset ring replaces a traditional border on glassy surfaces so it reads on both light and dark backgrounds without clipping.

### Spacing
8pt grid with 4pt half-steps. Tokens: `--space-1` (2), `--space-2` (4), `--space-3` (8), `--space-4` (12), `--space-5` (16), `--space-6` (20), `--space-7` (24), `--space-8` (32), `--space-9` (48), `--space-10` (64).

Inside a row of chrome (toolbar, titlebar): 8–12px horizontal gaps, 14px between an icon and its adjacent label. Inside content: 16px default, 24px between sections.

### Hover, press, focus
- **Hover** (mouse only — `@media (hover: hover)`): tint the control surface +4% alpha. Links don't underline on hover; they change color to `--blue`.
- **Press**: the surface drops to `fill-primary` (~10% black alpha) for fills, and text buttons darken by 15%. No scale/shrink — macOS controls don't physically shrink.
- **Focus ring**: 3px `rgba(0,122,255,0.5)` ring offset by 1.5px. Applied only on keyboard focus (`:focus-visible`). Buttons in macOS don't get focus rings by default in mouse-first flows; we follow the same rule.
- **Transitions** are fast: **120ms ease-out** for state changes, **200ms ease-in-out** for sheet/popover appearance, **400ms cubic-bezier(0.2, 0.8, 0.2, 1)** for window resize. No bouncy springs. No fade-and-slide-up marketing nonsense.

### Motion philosophy
macOS motion is functional: it explains a spatial change (this sheet came from this window) or confirms state (this checkbox ticked). quickbox follows the same rule. We never animate for delight-for-delight's-sake. The one exception: the dock icon bounces when a drop completes, because that's the OS language for "done".

### Borders & dividers
- **Dividers** between rows/sections: 1px `rgba(0,0,0,0.08)` on light, `rgba(255,255,255,0.1)` on dark.
- **Hairlines** on glass/window edges: 0.5px `rgba(0,0,0,0.23)` (heavier because it sits over a drop shadow).
- Borders on inputs: 1px `rgba(0,0,0,0.12)` default, `rgba(0,122,255,1)` focused.

### Imagery tone
- **Desktop wallpapers / backgrounds** visible behind the app are macOS-style: warm, saturated, dusk/dawn light. The app's surfaces adapt via materials, not by fighting the wallpaper.
- **File thumbnails** are rendered at actual aspect, light hairline border, no drop shadow (QuickLook-style).
- **Marketing or empty-state illustrations** (used sparingly) follow Apple's flat vector style: simple shapes, system colors, no gradients, no depth tricks. If in doubt, use an SF Symbol at 2x size instead of an illustration.

### Transparency & blur — when
- Chrome that sits over content (toolbars, sidebars, menu bar, popovers, sheets): **always glass**.
- Content areas inside the window: **opaque**. Blurring the content area makes reading files painful.
- Tooltips: **glass**, always.
- Modals that block the whole window: opaque sheet + dimmed background (`rgba(0,0,0,0.1)`).

### Layout rules
- Titlebars are 32px tall with 8px padding; traffic lights live in a 62×16 cluster at left.
- Toolbars immediately below titlebar are 44px tall (regular) or 52px (large title mode).
- Sidebars are 200–260px wide, resizable, snap to 200 / 240 / 280.
- The content area never extends under the window's rounded corners — respect the 16px radius with an `overflow: hidden` on the content container.
- Minimum window size: 480×320.

---

## Iconography

quickbox uses **SF Symbols** — Apple's system icon font — everywhere in the UI. SF Symbols is not redistributable; it lives on the user's Mac and Apple loads it at runtime. For these mockups and prototypes we substitute:

- **Primary substitute: Lucide** ([lucide.dev](https://lucide.dev)) — stroke-based, 1.5px weight, similar sizing and metaphors. Loaded via CDN in all preview/kit HTML.
- **Secondary substitute: Apple's SF Symbols PUA codepoints** (e.g. `􀈕`) — these appear literally in the Figma pseudocode because they're baked into SF Pro as private-use glyphs on a real Mac. They render as tofu on any other system. **Do not paste them into mockups** — they won't render for reviewers.
- **Tertiary: hand-drawn SVG** for the three or four quickbox-specific marks (the logo, the dock icon face). These live in `assets/icons/` as dedicated SVG files.

### Rules
- **16px in chrome** (toolbar, menu, row leading icon). Stroke weight 1.5px.
- **20px in sidebars and tab switchers**. Same stroke weight.
- **32–64px** in empty states and onboarding. Same icon, scaled.
- **Color inherits from `currentColor`** — never hardcode. An icon in a disabled row is automatically tertiary label color because the row sets `color`.
- **Icons never sit alone as interactive targets smaller than 28×28.** Pad the hit area.
- **No emoji, no Unicode symbols as icons** (no `⚙`, no `✉`). One exception: the traffic-light close/min/max glyphs, which are SVG not Unicode anyway.
- **Filled vs outlined**: outlined in chrome, filled when selected/active (standard Apple pattern).

### quickbox-specific marks
- `assets/logo/quickbox-wordmark.svg` — the full brand mark.
- `assets/logo/quickbox-monogram.svg` — "q" in a squircle, used as the app icon and menu-bar icon.
- `assets/icons/drop-zone.svg` — the dashed-outline box used in the main drop surface.

---

## Font substitution notice

**SF Pro and SF Pro Rounded are Apple's proprietary fonts.** We cannot redistribute them. In `fonts/` we ship the closest Google Fonts match:

- **SF Pro → Inter** (weights 400/500/600/700/800). Inter was designed for UI and has near-identical metrics to SF Pro at 13–17px body sizes. Some kerning at large display sizes will differ.
- **SF Pro Rounded → Nunito** (weights 400/500/700). Nunito is a reasonable geometric-rounded substitute.

**Action item for a real build:** license SF Pro via Apple's developer agreement if shipping a Mac app (it's effectively free for macOS app use), or swap in a purchased font.

---

## How to use this system

For design / prototyping: import `colors_and_type.css` and pull tokens. Use kit components from `ui_kits/quickbox-mac/`. For production macOS app code this folder is reference only — the real app uses SwiftUI + AppKit standard controls.
