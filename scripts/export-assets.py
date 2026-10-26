#!/usr/bin/env python3
"""Export the brand files in assets/ to what the app ships.

  assets/logo_corto.png -> assets/app-icon/AppIcon.png   (1024x1024, opaque, vanilla background)
  assets/logo.png       -> Sources/DesignSystem/Resources/wordmark.png  (trimmed, 240 px tall)

Without logo_corto.png it draws a placeholder "C". Without logo.png the app shows
"CareHold" in serif instead of the image. Run it again whenever a logo changes.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
ICON = ASSETS / "app-icon" / "AppIcon.png"
WORDMARK = ROOT / "Sources" / "DesignSystem" / "Resources" / "wordmark.png"
VANILLA = (250, 246, 238)
SAGE = (70, 112, 95)


def trimmed(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    box = image.getchannel("A").getbbox()
    return image.crop(box) if box else image


def export_icon() -> None:
    source = ASSETS / "logo_corto.png"
    canvas = Image.new("RGB", (1024, 1024), VANILLA)
    if source.exists():
        logo = Image.open(source).convert("RGBA")
        opaque = logo.getchannel("A").getextrema()[0] == 255
        if opaque and abs(logo.width - logo.height) <= 2:
            # Already a full square icon: use it as is (iOS rounds the corners).
            canvas = logo.convert("RGB").resize((1024, 1024), Image.LANCZOS)
        else:
            logo = trimmed(logo)
            scale = 640 / max(logo.width, logo.height)
            logo = logo.resize((round(logo.width * scale), round(logo.height * scale)), Image.LANCZOS)
            canvas.paste(logo, ((1024 - logo.width) // 2, (1024 - logo.height) // 2), logo)
        print(f"icon from {source.name}")
    else:
        draw = ImageDraw.Draw(canvas)
        font = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSerif-SemiBold.ttf", 600)
        left, top, right, bottom = draw.textbbox((0, 0), "C", font=font)
        draw.text(((1024 - (right - left)) / 2 - left, (1024 - (bottom - top)) / 2 - top), "C", font=font, fill=SAGE)
        print("icon placeholder (add assets/logo_corto.png)")
    ICON.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(ICON)


def export_wordmark() -> None:
    source = ASSETS / "logo.png"
    if not source.exists():
        WORDMARK.unlink(missing_ok=True)
        print("no wordmark (add assets/logo.png); the app shows the name in serif")
        return
    logo = trimmed(Image.open(source))
    scale = 240 / logo.height
    logo = logo.resize((round(logo.width * scale), 240), Image.LANCZOS)
    WORDMARK.parent.mkdir(parents=True, exist_ok=True)
    logo.save(WORDMARK)
    print(f"wordmark from {source.name}")


if __name__ == "__main__":
    export_icon()
    export_wordmark()
