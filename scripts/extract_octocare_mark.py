"""Build a true transparent octopus mark from the solid app icon (no checkerboard)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT / "assets" / "branding" / "octocare_app_icon.png"
OUT = ROOT / "assets" / "branding" / "octocare_mark.png"
FLUTTER_MARK = ROOT / "smart_clinic" / "assets" / "images" / "octocare_mark.png"

TEAL = (0, 168, 181)


def extract_mark(source: Path) -> Image.Image:
    img = Image.open(source).convert("RGBA")
    pixels = img.load()
    width, height = img.size
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    out_pixels = out.load()

    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[x, y]
            # White octopus strokes on the launcher icon.
            brightness = (r + g + b) / 3
            if brightness < 150:
                continue
            alpha = int(min(255, max(0, (brightness - 120) * 1.8)))
            if alpha < 20:
                continue
            out_pixels[x, y] = (*TEAL, alpha)

    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)

    # Add a little breathing room for UI scaling.
    padded = Image.new("RGBA", (out.width + 40, out.height + 40), (0, 0, 0, 0))
    padded.paste(out, (20, 20), out)
    return padded


def main() -> None:
    mark = extract_mark(ICON)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    mark.save(OUT, format="PNG")
    FLUTTER_MARK.parent.mkdir(parents=True, exist_ok=True)
    mark.save(FLUTTER_MARK, format="PNG")
    print(f"Wrote {OUT}")
    print(f"Wrote {FLUTTER_MARK}")


if __name__ == "__main__":
    main()
