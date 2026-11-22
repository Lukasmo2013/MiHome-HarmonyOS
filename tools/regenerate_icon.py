#!/usr/bin/env python3
"""生成 MiHome 浅蓝绿图标（普通图标 + 自适应前景/背景）。"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
TOP = (173, 232, 228)     # #ADE8E4 浅蓝绿
BOTTOM = (96, 190, 199)   # #60BEC7 蓝绿
SCALE = 4


def gradient(size: int) -> Image.Image:
    small = Image.new('RGB', (1, size))
    px = small.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px[0, y] = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    return small.resize((size, size), Image.Resampling.BICUBIC)


def draw_mark(size: int, pad_ratio: float = 0.24) -> Image.Image:
    """透明底上绘制白色 M 盾牌。"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size * SCALE
    img_s = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img_s)

    x0, x1 = s * pad_ratio, s * (1 - pad_ratio)
    y0, y1 = s * (pad_ratio + 0.02), s * (1 - pad_ratio - 0.02)
    w = max(8, int(s * 0.038))

    # 上半部：M 形折线
    pts = [
        (x0, y0 + (y1 - y0) * 0.38),
        (x0, y0),
        (x0 + (x1 - x0) * 0.23, y0 + (y1 - y0) * 0.14),
        ((x0 + x1) / 2, y0 + (y1 - y0) * 0.05),
        (x0 + (x1 - x0) * 0.77, y0 + (y1 - y0) * 0.14),
        (x1, y0),
        (x1, y0 + (y1 - y0) * 0.38),
    ]
    d.line(pts, fill=(255, 255, 255, 255), width=w, joint='curve')
    for p in (pts[0], pts[1], pts[2], pts[3], pts[4], pts[5], pts[6]):
        r = w // 2
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(255, 255, 255, 255))

    # 下半部：圆润碗形
    bowl = [
        x0 + w // 2,
        y0 + (y1 - y0) * 0.26,
        x1 - w // 2,
        y1 - w // 2,
    ]
    d.arc(bowl, start=0, end=180, fill=(255, 255, 255, 255), width=w)
    r = w // 2
    cy = (bowl[1] + bowl[3]) // 2
    d.ellipse([bowl[0] - r, cy - r, bowl[0] + r, cy + r], fill=(255, 255, 255, 255))
    d.ellipse([bowl[2] - r, cy - r, bowl[2] + r, cy + r], fill=(255, 255, 255, 255))

    return img_s.resize((size, size), Image.Resampling.LANCZOS)


def save_all() -> None:
    targets = [
        ROOT / 'AppScope' / 'resources' / 'base' / 'media',
        ROOT / 'entry' / 'src' / 'main' / 'resources' / 'base' / 'media',
    ]

    ico = gradient(512 * SCALE).resize((512, 512), Image.Resampling.LANCZOS).convert('RGBA')
    ico.alpha_composite(draw_mark(512, 0.24))

    fg = draw_mark(1024, 0.25)
    bg = gradient(1024 * SCALE).resize((1024, 1024), Image.Resampling.LANCZOS).convert('RGBA')

    for folder in targets:
        folder.mkdir(parents=True, exist_ok=True)
        ico.save(folder / 'ico.png')
        bg.save(folder / 'background.png')
        fg.save(folder / 'foreground.png')
        print('wrote', folder)


if __name__ == '__main__':
    save_all()
