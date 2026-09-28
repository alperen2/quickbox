"""Regenerates the macOS app icon and menu bar icon from the brand master.

Run from the repository root (needs Pillow):
    python3 brand/make_icons.py

The app icon is the white mark on a coral tile, laid out on Apple's macOS icon grid:
a 824px rounded square with a soft shadow on a 1024px canvas.

The menu bar icon is a template image of the mark. Its small enclosed gaps (inside the
headset) are filled so the headset stays a solid shape at 16pt instead of turning to mush.
"""
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "brand/source/pigeon-mark-4320.png"
APP_ICON_SET = ROOT / "quickbox/Assets.xcassets/AppIcon.appiconset"
MENU_BAR_ICON_SET = ROOT / "quickbox/Assets.xcassets/MenuBarIcon.imageset"
MENU_BAR_POINTS = 16

CORAL = (0xF3, 0x61, 0x75, 255)
WHITE = (255, 255, 255, 255)
CANVAS = 1024
TILE = (100, 100, 924, 924)
TILE_RADIUS = 186
MARK_HEIGHT = 560


def app_icon() -> Image.Image:
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((TILE[0], TILE[1] + 12, TILE[2], TILE[3] + 12), TILE_RADIUS, fill=(0, 0, 0, 90))
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))

    tile = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle(TILE, TILE_RADIUS, fill=CORAL)
    icon.alpha_composite(tile)

    master = Image.open(MASTER)
    width = round(master.width * MARK_HEIGHT / master.height)
    alpha = master.getchannel("A").resize((width, MARK_HEIGHT), Image.LANCZOS)
    mark = Image.new("RGBA", alpha.size, WHITE)
    mark.putalpha(alpha)
    icon.alpha_composite(mark, ((CANVAS - width) // 2, (CANVAS - MARK_HEIGHT) // 2))
    return icon


def fill_enclosed_gaps(mask: Image.Image) -> Image.Image:
    """Makes transparent areas that don't reach the canvas edge opaque."""
    width, height = mask.size
    pixels = mask.load()
    reaches_edge = [[False] * width for _ in range(height)]
    queue = deque((x, y) for x in range(width) for y in (0, height - 1))
    queue.extend((x, y) for y in range(height) for x in (0, width - 1))
    while queue:
        x, y = queue.popleft()
        if not (0 <= x < width and 0 <= y < height) or reaches_edge[y][x] or pixels[x, y] != 0:
            continue
        reaches_edge[y][x] = True
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    filled = mask.copy()
    out = filled.load()
    for y in range(height):
        for x in range(width):
            if pixels[x, y] == 0 and not reaches_edge[y][x]:
                out[x, y] = 255
    return filled


def menu_bar_icon(points: int, scale: int) -> Image.Image:
    alpha = Image.open(MASTER).getchannel("A")
    work = alpha.resize((alpha.width // 4, alpha.height // 4), Image.LANCZOS).point(lambda v: 255 if v > 127 else 0)
    work = fill_enclosed_gaps(work)
    height = points * scale
    width = round(work.width * height / work.height)
    icon = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    icon.putalpha(work.resize((width, height), Image.LANCZOS))
    return icon


def main() -> None:
    icon = app_icon()
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "" if scale == 1 else "@2x"
            size = points * scale
            icon.resize((size, size), Image.LANCZOS).save(APP_ICON_SET / f"icon_{points}x{points}{suffix}.png", optimize=True)
    print(f"Wrote {APP_ICON_SET.relative_to(ROOT)}")

    MENU_BAR_ICON_SET.mkdir(exist_ok=True)
    for scale in (1, 2):
        suffix = "" if scale == 1 else "@2x"
        menu_bar_icon(MENU_BAR_POINTS, scale).save(MENU_BAR_ICON_SET / f"menubar-icon{suffix}.png", optimize=True)
    print(f"Wrote {MENU_BAR_ICON_SET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
