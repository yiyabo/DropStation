from pathlib import Path
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit("缺少 Pillow：请先运行 python3 -m pip install --user Pillow 再重新构建")

# DMG 安装窗口为 660x400 点，按 2x 绘制保证视网膜屏下清晰
SCALE = 2
WIDTH, HEIGHT = 660 * SCALE, 400 * SCALE

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("dist/.background/background.png")


def load_font(size):
    for name in (
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
    ):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return None


def pt(value):
    return value * SCALE


image = Image.new("RGBA", (WIDTH, HEIGHT))
draw = ImageDraw.Draw(image)

# 深蓝→紫渐变，与应用图标配色一致
top = (30, 40, 84)
bottom = (56, 28, 96)
for y in range(HEIGHT):
    t = y / (HEIGHT - 1)
    color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    draw.line([(0, y), (WIDTH - 1, y)], fill=color + (255,))

# 应用图标（左）→ Applications（右）的拖拽方向引导箭头
arrow_color = (255, 255, 255, 110)
y = pt(170)
draw.rounded_rectangle((pt(258), y - pt(5), pt(402), y + pt(5)), radius=pt(5), fill=arrow_color)
draw.polygon([(pt(396), y - pt(16)), (pt(430), y), (pt(396), y + pt(16))], fill=arrow_color)

title_font = load_font(pt(21))
if title_font:
    title = "DropStation"
    bbox = draw.textbbox((0, 0), title, font=title_font)
    draw.text(((WIDTH - (bbox[2] - bbox[0])) / 2, pt(44)), title, font=title_font, fill=(255, 255, 255, 215))

hint_font = load_font(pt(15))
if hint_font:
    hint = "将 DropStation 拖入 Applications 文件夹完成安装"
    bbox = draw.textbbox((0, 0), hint, font=hint_font)
    draw.text(((WIDTH - (bbox[2] - bbox[0])) / 2, pt(320)), hint, font=hint_font, fill=(255, 255, 255, 160))

OUT.parent.mkdir(parents=True, exist_ok=True)
image.save(OUT)
