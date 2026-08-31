from pathlib import Path
import subprocess

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    raise SystemExit("缺少 Pillow：请先运行 python3 -m pip install --user Pillow 再重新构建")

ROOT = Path(__file__).resolve().parent
ICONSET = ROOT / ".build" / "DropStation.iconset"
ICONSET.mkdir(parents=True, exist_ok=True)
for path in ICONSET.glob("*.png"):
    path.unlink()

SCALE = 4
CANVAS = 1024


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def make_icon():
    image = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((92, 110, 932, 950), radius=190, fill=(12, 10, 40, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(42))
    image.alpha_composite(shadow)

    background = Image.new("RGBA", image.size, (0, 0, 0, 0))
    pixels = background.load()
    for y in range(CANVAS):
        for x in range(CANVAS):
            t = (x * 0.72 + y * 0.28) / (CANVAS - 1)
            top = (70, 112, 245)
            bottom = (125, 61, 218)
            pixels[x, y] = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,)
    background.putalpha(rounded_mask(CANVAS, 190))
    image.alpha_composite(background)

    highlight = Image.new("RGBA", image.size, (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.ellipse((-210, -240, 620, 500), fill=(255, 255, 255, 46))
    highlight = highlight.filter(ImageFilter.GaussianBlur(70))
    highlight.putalpha(Image.composite(highlight.getchannel("A"), Image.new("L", image.size, 0), rounded_mask(CANVAS, 190)))
    image.alpha_composite(highlight)

    cards = [
        ((252, 270, 770, 776), (230, 237, 255, 235), 48),
        ((300, 220, 818, 726), (248, 250, 255, 255), 48),
    ]
    for box, color, radius in cards:
        card = Image.new("RGBA", image.size, (0, 0, 0, 0))
        card_draw = ImageDraw.Draw(card)
        card_draw.rounded_rectangle(box, radius=radius, fill=color, outline=(255, 255, 255, 120), width=5)
        image.alpha_composite(card)

    card_draw = ImageDraw.Draw(image)
    card_draw.polygon([(700, 220), (818, 220), (818, 338)], fill=(211, 220, 247, 255))
    card_draw.line([(700, 220), (700, 338), (818, 338)], fill=(179, 193, 231, 180), width=4)

    for y, width in [(400, 285), (455, 350), (510, 300)]:
        card_draw.rounded_rectangle((375, y, 375 + width, y + 18), radius=9, fill=(116, 137, 196, 100))
    card_draw.rounded_rectangle((375, 590, 560, 608), radius=9, fill=(116, 137, 196, 75))

    arrow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    arrow_draw = ImageDraw.Draw(arrow)
    arrow_draw.rounded_rectangle((488, 530, 536, 692), radius=22, fill=(73, 94, 184, 255))
    arrow_draw.polygon([(408, 646), (512, 750), (616, 646), (574, 604), (512, 666), (450, 604)], fill=(73, 94, 184, 255))
    image.alpha_composite(arrow)

    gloss = Image.new("RGBA", image.size, (0, 0, 0, 0))
    gloss_draw = ImageDraw.Draw(gloss)
    gloss_draw.rounded_rectangle((108, 108, 916, 916), radius=178, outline=(255, 255, 255, 52), width=8)
    image.alpha_composite(gloss)
    return image


icon = make_icon()
icon.save(ICONSET / "icon_512x512@2x.png")
for pixels, filename in [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
]:
    icon.resize((pixels, pixels), Image.Resampling.LANCZOS).save(ICONSET / filename)

subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ROOT / ".build" / "DropStation.icns")], check=True)
