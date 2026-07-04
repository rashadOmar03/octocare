"""Generate Octocare launcher icons for Android, iOS, and web from the master app icon."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICON_MASTER = ROOT / "assets" / "branding" / "octocare_app_icon.png"
LOGO_MASTER = ROOT / "assets" / "branding" / "octocare_logo.png"
FLUTTER = ROOT / "smart_clinic"

ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

WEB_ICONS = {
    "favicon.png": 32,
    "icons/Icon-192.png": 192,
    "icons/Icon-512.png": 512,
    "icons/Icon-maskable-192.png": 192,
    "icons/Icon-maskable-512.png": 512,
}

ANDROID_SPLASH = FLUTTER / "android" / "app" / "src" / "main" / "res" / "drawable" / "splash_logo.png"
IOS_SPLASH_DIR = FLUTTER / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
IOS_SPLASH_SIZES = {
    "LaunchImage.png": 168,
    "LaunchImage@2x.png": 336,
    "LaunchImage@3x.png": 504,
}


def save_square(image: Image.Image, size: int, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(path, format="PNG", optimize=True)


def save_maskable(image: Image.Image, size: int, path: Path, padding_ratio: float = 0.18) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (size, size), (0, 168, 181, 255))
    inner = int(size * (1 - padding_ratio * 2))
    icon = image.resize((inner, inner), Image.Resampling.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(icon, (offset, offset), icon if icon.mode == "RGBA" else None)
    canvas.save(path, format="PNG", optimize=True)


def main() -> None:
    if not ICON_MASTER.exists():
        raise SystemExit(f"Missing icon master: {ICON_MASTER}")

    icon = Image.open(ICON_MASTER).convert("RGBA")

    for folder, size in ANDROID_SIZES.items():
        target = FLUTTER / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png"
        save_square(icon, size, target)
        print(f"Wrote {target}")

    ios_dir = FLUTTER / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for filename, size in IOS_ICONS.items():
        target = ios_dir / filename
        save_square(icon, size, target)
        print(f"Wrote {target}")

    for rel_path, size in WEB_ICONS.items():
        target = FLUTTER / "web" / rel_path
        if "maskable" in rel_path:
            save_maskable(icon, size, target)
        else:
            save_square(icon, size, target)
        print(f"Wrote {target}")

    app_assets = FLUTTER / "assets" / "images"
    save_square(icon, 512, app_assets / "app_icon.png")
    logo = Image.open(LOGO_MASTER).convert("RGBA")
    logo.save(app_assets / "octocare_logo.png", format="PNG", optimize=True)
    print(f"Wrote {app_assets / 'octocare_logo.png'}")

    splash_source = logo.copy()
    for filename, size in IOS_SPLASH_SIZES.items():
        canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
        inner = int(size * 0.72)
        item = splash_source.copy()
        item.thumbnail((inner, inner), Image.Resampling.LANCZOS)
        offset = ((size - item.width) // 2, (size - item.height) // 2)
        canvas.paste(item, offset, item)
        target = IOS_SPLASH_DIR / filename
        canvas.save(target, format="PNG", optimize=True)
        print(f"Wrote {target}")

    splash_android = Image.new("RGBA", (512, 512), (255, 255, 255, 255))
    item = splash_source.copy()
    item.thumbnail((360, 360), Image.Resampling.LANCZOS)
    offset = ((512 - item.width) // 2, (512 - item.height) // 2)
    splash_android.paste(item, offset, item)
    ANDROID_SPLASH.parent.mkdir(parents=True, exist_ok=True)
    splash_android.save(ANDROID_SPLASH, format="PNG", optimize=True)
    print(f"Wrote {ANDROID_SPLASH}")


if __name__ == "__main__":
    main()
