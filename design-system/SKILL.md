---
name: quickbox-design
description: Use this skill to generate well-branded interfaces and assets for quickbox, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping.
user-invocable: true
---

Read the README.md file within this skill, and explore the other available files.

quickbox is a macOS-native file-drop app. The design system is built on top of the macOS 26 (Tahoe) design language — SF Pro type, system accent colors, Liquid Glass materials, and Apple HIG component behavior — with `--brand` (warm orange `#FF9500`) as the quickbox accent.

Key files:
- `README.md` — full brand, content, and visual foundations.
- `colors_and_type.css` — drop-in tokens (colors, type, radii, shadows, spacing, materials).
- `assets/logo/` — monogram + wordmark SVGs. Use these, don't redraw.
- `assets/icons/` — quickbox-specific marks (drop-zone).
- `preview/*.html` — token + component cards.
- `ui_kits/quickbox-mac/` — JSX + HTML recreation of the Mac app; copy components from here instead of rebuilding.

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. Always link `colors_and_type.css` at the top of any new HTML so tokens are available.

If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand. The production Mac app should use native SwiftUI/AppKit controls — this folder is design reference, not a component library to ship.

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

Essentials to remember:
- Voice: direct, sentence-case, verbs for buttons, no emoji in UI.
- Type: SF Pro (fallback Inter). Body is 13px — correct for macOS, not "too small".
- Materials: Liquid Glass (blur + saturate) for chrome (toolbars, sidebars, popovers); opaque for content areas.
- Shadows are tight: 0.5px hairline + soft drop. Not big diffuse glows.
- Corners: 6 for buttons/rows, 10 for cards, 16 for windows/sheets.
- Iconography: Lucide (1.5px stroke) substitutes SF Symbols. Don't use emoji or hand-rolled SVG icons.
- Motion: 120–200ms, `cubic-bezier(0.2, 0.8, 0.2, 1)`. No bouncy springs.
