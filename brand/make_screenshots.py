"""Composes the Mac App Store screenshots from the raw app renders.

1. Render the app views (no screen access needed):
       TEST_RUNNER_PIGEON_SCREENSHOTS_DIR=/tmp/pigeon-shots xcodebuild test -project quickbox.xcodeproj \
         -scheme quickbox-AppStore -destination 'platform=macOS' -only-testing:quickboxTests/AppStoreScreenshots
2. Compose them (needs Pillow):
       python3 brand/make_screenshots.py /tmp/pigeon-shots

Writes 2880x1800 PNGs to fastlane/screenshots/en-US, where `fastlane deliver` picks them up.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "fastlane/screenshots/en-US"
MARK = ROOT / "brand/source/pigeon-mark-4320.png"
FONT = "/System/Library/Fonts/SFNS.ttf"

SIZE = (2880, 1800)
CORAL = (0xF3, 0x61, 0x75)
CORAL_DEEP = (0xD1, 0x42, 0x5A)
WHITE = (255, 255, 255)

SHOTS = [
    ("1-capture", "Capture a thought in a second.", "Press ⌘⇧Space anywhere, type, and get back to work."),
    ("2-agents", "Hand work to your AI agents.", "Tag a task for:agent. Claude, ChatGPT or any MCP client picks it up."),
    ("3-handback", "Agents hand the next step back.", "Their results come back as tasks for you, in plain Markdown files."),
]


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(FONT, size)
    face.set_variation_by_name(weight)
    return face


def background() -> Image.Image:
    """A soft vertical coral gradient."""
    canvas = Image.new("RGB", SIZE, CORAL)
    draw = ImageDraw.Draw(canvas)
    for y in range(SIZE[1]):
        t = y / (SIZE[1] - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(CORAL, CORAL_DEEP))
        draw.line([(0, y), (SIZE[0], y)], fill=color)
    return canvas.convert("RGBA")


def white_mark(height: int) -> Image.Image:
    alpha = Image.open(MARK).getchannel("A")
    width = round(alpha.width * height / alpha.height)
    mark = Image.new("RGBA", (width, height), WHITE + (255,))
    mark.putalpha(alpha.resize((width, height), Image.LANCZOS))
    return mark


def compose(render: Image.Image, title: str, subtitle: str) -> Image.Image:
    canvas = background()
    draw = ImageDraw.Draw(canvas)

    mark = white_mark(120)
    canvas.alpha_composite(mark, ((SIZE[0] - mark.width) // 2, 90))

    title_font, subtitle_font = font(120, "Bold"), font(60, "Medium")
    for text, face, y, fill in ((title, title_font, 250, WHITE), (subtitle, subtitle_font, 400, (255, 255, 255, 225))):
        width = draw.textlength(text, font=face)
        draw.text(((SIZE[0] - width) / 2, y), text, font=face, fill=fill)

    top, bottom_margin = 520, 40
    scale = min((SIZE[1] - top - bottom_margin) / render.height, (SIZE[0] - 400) / render.width)
    shot = render.resize((round(render.width * scale), round(render.height * scale)), Image.LANCZOS)
    canvas.alpha_composite(shot, ((SIZE[0] - shot.width) // 2, top))
    return canvas.convert("RGB")


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    renders = Path(sys.argv[1])
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, title, subtitle in SHOTS:
        render = Image.open(renders / f"{name}.png").convert("RGBA")
        compose(render, title, subtitle).save(OUTPUT / f"{name}.png", optimize=True)
        print(f"Wrote {(OUTPUT / f'{name}.png').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
