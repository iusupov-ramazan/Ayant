#!/usr/bin/env python3
"""Собирает витринные скриншоты App Store из сырых захватов симулятора.

Вход:  docs/appstore/screenshots/raw-ru/NN-*.png и raw-en/ (1320×2868, iPhone 6.9")
Выход: docs/appstore/screenshots/framed/<lang>/NN-<lang>.png — тот же размер,
       фирменный градиент, подпись сверху, экран со скруглёнными углами.

Запуск: python3 docs/appstore/make_screenshots.py
Подписи — в CAPTIONS ниже; кадр без подписи пропускается с предупреждением.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "screenshots" / "raw"
OUT = ROOT / "screenshots" / "framed"
W, H = 1320, 2868

# Подписи по номеру кадра: (заголовок, подзаголовок) для ru и en.
CAPTIONS = {
    "01": {"ru": ("Все акции Бишкека", "в одной ленте"),
           "en": ("Every deal in Bishkek", "in one feed")},
    "02": {"ru": ("Все заведения", "рядом с вами"),
           "en": ("Every venue", "near you")},
    "03": {"ru": ("Часы, маршрут, звонок", "в одно касание"),
           "en": ("Hours, directions, call", "in one tap")},
    "04": {"ru": ("Купон в приложении,", "QR — сотруднику"),
           "en": ("Coupon in the app,", "QR for the staff")},
    "05": {"ru": ("Покажите QR —", "копите баллы"),
           "en": ("Show your QR —", "earn points")},
    "06": {"ru": ("Баллы и штампы", "у каждого заведения"),
           "en": ("Points and stamps", "at every venue")},
    "07": {"ru": ("Награда", "за каждый визит"),
           "en": ("A reward", "for every visit")},
}

FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_REG = "/System/Library/Fonts/Supplemental/Arial.ttf"

# Фирменный градиент (как на экране входа): оранжевый → янтарный.
TOP = (255, 77, 41)
BOTTOM = (255, 179, 0)


def gradient() -> Image.Image:
    img = Image.new("RGB", (W, H), TOP)
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        c = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(W):
            px[x, y] = c
    return img


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def frame(raw: Path, title: str, subtitle: str, out: Path) -> None:
    bg = gradient().convert("RGBA")
    draw = ImageDraw.Draw(bg)
    f_title = ImageFont.truetype(FONT_BOLD, 96)
    f_sub = ImageFont.truetype(FONT_REG, 66)

    y = 190
    for text, font in ((title, f_title), (subtitle, f_sub)):
        # Подпись не должна упираться в края: уменьшаем кегль, пока не влезет.
        size = font.size
        while draw.textlength(text, font=font) > W - 160 and size > 40:
            size -= 4
            font = ImageFont.truetype(font.path, size)
        w = draw.textlength(text, font=font)
        draw.text(((W - w) / 2, y), text, font=font, fill=(255, 255, 255))
        y += (font.size + 22)

    shot = Image.open(raw).convert("RGB")
    scale = 0.84
    sw, sh = round(W * scale), round(H * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    shot = rounded(shot, radius=110)

    x = (W - sw) // 2
    top = 470
    # Мягкая тень под экраном.
    shadow = Image.new("RGBA", (sw + 120, sh + 120), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([60, 60, sw + 60, sh + 60], radius=110, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    bg.alpha_composite(shadow, (x - 60, top - 40))
    bg.alpha_composite(shot, (x, top))

    # Низ экрана уходит за край кадра — так принято в витринах, важна верхняя часть.
    bg = bg.crop((0, 0, W, H)).convert("RGB")
    bg.save(out, "PNG", optimize=True)
    print("wrote", out.relative_to(ROOT.parent.parent))


def main() -> None:
    # Захваты по языкам: raw-ru/ и raw-en/ — контент экрана на том же языке,
    # что и подпись. Старый общий raw/ поддерживается как запасной вариант.
    for lang in ("ru", "en"):
        raw_dir = ROOT / "screenshots" / f"raw-{lang}"
        if not raw_dir.exists():
            raw_dir = RAW
        raws = sorted(raw_dir.glob("[0-9][0-9]-*.png"))
        if not raws:
            print(f"no captures for {lang} in {raw_dir}")
            continue
        out_dir = OUT / lang
        out_dir.mkdir(parents=True, exist_ok=True)
        for raw in raws:
            num = raw.name[:2]
            caps = CAPTIONS.get(num)
            if not caps or lang not in caps:
                print("skip (no caption):", raw.name)
                continue
            title, subtitle = caps[lang]
            frame(raw, title, subtitle, out_dir / f"{num}-{lang}.png")


if __name__ == "__main__":
    main()
