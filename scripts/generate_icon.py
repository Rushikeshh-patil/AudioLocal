#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


SIZE = 1024
ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
ICONSET = DIST / "AudioLocal.iconset"
ICNS = DIST / "AudioLocal.icns"
PREVIEW = DIST / "icon-preview.png"


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def gradient_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    top_left = (20, 29, 43)
    top_right = (24, 71, 92)
    bottom_left = (12, 46, 66)
    bottom_right = (240, 132, 74)

    for y in range(size):
        ty = y / (size - 1)
        for x in range(size):
            tx = x / (size - 1)
            left = tuple(lerp(top_left[i], bottom_left[i], ty) for i in range(3))
            right = tuple(lerp(top_right[i], bottom_right[i], ty) for i in range(3))
            color = tuple(lerp(left[i], right[i], tx) for i in range(3))
            pixels[x, y] = (*color, 255)
    return image


def add_glow(image: Image.Image, box: tuple[int, int, int, int], color: tuple[int, int, int, int], blur: int) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box, fill=color)
    image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def rounded_mask(size: int, inset: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((inset, inset, size - inset, size - inset), radius=radius, fill=255)
    return mask


def draw_waveform(draw: ImageDraw.ImageDraw, origin: tuple[int, int]) -> None:
    x0, y0 = origin
    widths = 20
    gap = 16
    heights = [78, 114, 168, 214, 148, 236, 174]
    colors = [
        (72, 203, 184),
        (84, 198, 182),
        (110, 194, 180),
        (255, 153, 92),
        (255, 173, 104),
        (255, 141, 86),
        (239, 126, 82),
    ]
    for index, height in enumerate(heights):
        left = x0 + index * (widths + gap)
        top = y0 - height // 2
        draw.rounded_rectangle(
            (left, top, left + widths, top + height),
            radius=10,
            fill=colors[index],
        )


def build_master_icon() -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((72, 88, 952, 968), radius=220, fill=(0, 0, 0, 165))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(40)), dest=(0, 0))

    base = gradient_background(SIZE)
    add_glow(base, (80, 680, 620, 1160), (57, 212, 187, 110), 110)
    add_glow(base, (560, 40, 1080, 560), (255, 171, 89, 160), 120)
    add_glow(base, (420, 230, 1000, 840), (255, 245, 231, 48), 140)

    base_mask = rounded_mask(SIZE, 52, 220)
    clipped_base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    clipped_base.paste(base, mask=base_mask)
    canvas.alpha_composite(clipped_base)

    border = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border)
    border_draw.rounded_rectangle(
        (54, 54, 970, 970),
        radius=220,
        outline=(255, 255, 255, 36),
        width=4,
    )
    canvas.alpha_composite(border)

    card_shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    card_shadow_draw = ImageDraw.Draw(card_shadow)
    card_shadow_draw.rounded_rectangle((188, 202, 836, 786), radius=86, fill=(0, 0, 0, 70))
    canvas.alpha_composite(card_shadow.filter(ImageFilter.GaussianBlur(28)))

    card = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    card_draw = ImageDraw.Draw(card)
    card_draw.rounded_rectangle((176, 186, 824, 770), radius=84, fill=(245, 240, 231, 255))
    card_draw.rounded_rectangle((176, 186, 824, 770), radius=84, outline=(255, 255, 255, 120), width=4)
    card_draw.rounded_rectangle((226, 230, 402, 260), radius=15, fill=(226, 216, 204, 255))
    canvas.alpha_composite(card)

    accents = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    accents_draw = ImageDraw.Draw(accents)

    line_color = (57, 77, 90, 255)
    line_specs = [
        (226, 302, 458, 332),
        (226, 356, 486, 386),
        (226, 410, 438, 440),
        (226, 464, 404, 494),
    ]
    for spec in line_specs:
        accents_draw.rounded_rectangle(spec, radius=14, fill=line_color)

    accents_draw.rounded_rectangle((516, 256, 756, 540), radius=42, fill=(228, 246, 244, 255))
    draw_waveform(accents_draw, (552, 398))

    badge_box = (604, 564, 804, 764)
    accents_draw.ellipse(badge_box, fill=(255, 145, 82, 255))
    accents_draw.ellipse((620, 580, 788, 748), outline=(255, 219, 196, 120), width=4)
    accents_draw.polygon([(676, 612), (676, 716), (752, 664)], fill=(255, 248, 241, 255))
    canvas.alpha_composite(accents)

    ring = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ring_draw = ImageDraw.Draw(ring)
    ring_draw.arc((594, 554, 814, 774), start=210, end=330, fill=(255, 214, 182, 180), width=10)
    ring_draw.arc((574, 534, 834, 794), start=214, end=326, fill=(255, 233, 214, 90), width=8)
    canvas.alpha_composite(ring.filter(ImageFilter.GaussianBlur(1)))

    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.rounded_rectangle((96, 68, 928, 280), radius=180, fill=(255, 255, 255, 40))
    highlight_draw.ellipse((160, 96, 460, 286), fill=(255, 255, 255, 26))
    canvas.alpha_composite(highlight.filter(ImageFilter.GaussianBlur(18)))

    alpha = canvas.getchannel("A")
    alpha = ImageChops.multiply(alpha, rounded_mask(SIZE, 52, 220))
    canvas.putalpha(alpha)
    return canvas


def save_iconset(master: Image.Image) -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    ICONSET.mkdir(parents=True, exist_ok=True)

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    for filename, edge in sizes.items():
        resized = master.resize((edge, edge), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename)

    master.save(PREVIEW)


def main() -> None:
    master = build_master_icon()
    save_iconset(master)


if __name__ == "__main__":
    main()
