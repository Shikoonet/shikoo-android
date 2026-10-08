#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow==12.3.0", "potracer==0.0.4"]
# ///
"""Writes every Shikoo brand image from one source, assets/brand/logo-source.jpg.

The source is a gold mark on pure black: the fox on top, the word SHIKOONET under it, then a thin
line, which is left out. To change the brand, replace that file and run from the repository root:

    source ~/android-toolchain/env.sh && uv run tools/shikoo-brand.py

It overwrites the launcher, round, TV and Play icons, the adaptive foreground (also the Android 12+
splash icon), the TV banner, the notification and quick-settings icon, and the in-app mark.
Each file carries MARK, which test/shikoo/brand_test.dart looks for.
"""

from pathlib import Path

import potrace
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat, PngImagePlugin

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'assets/brand/logo-source.jpg'
RES = ROOT / 'android/app/src/main/res'
SERVICE = ROOT / 'android/service/src/main/res/drawable'
MARK = 'shikoo-brand'
DENSITY = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
LIT = 40  # the darkest channel value still counted as the mark, for finding its parts
SS = 4  # supersampling for the drawn shapes' edges


def save(im, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == '.webp':
        im.save(path, lossless=True, xmp=MARK.encode())
    else:
        info = PngImagePlugin.PngInfo()
        info.add_text('Software', MARK)
        im.save(path, pnginfo=info, optimize=True)
    print(path.relative_to(ROOT), im.size)


def parts(lit):
    """Boxes of the runs of lit rows, top to bottom, trimmed to their lit columns, 3px to spare."""
    rows = [lit.crop((0, y, lit.width, y + 1)).getbbox() is not None for y in range(lit.height)]
    boxes, top = [], None
    for y, on in enumerate(rows + [False]):
        if on and top is None:
            top = y
        elif not on and top is not None:
            x0, _, x1, _ = lit.crop((0, top, lit.width, y)).getbbox()
            boxes.append((x0 - 3, top - 3, x1 + 3, y + 3))
            top = None
    return boxes


def cut(src, peak, box):
    """The source inside box with its black turned transparent: on black it looks the same."""
    a = peak.crop(box).point(lambda v: max(0, min(255, (v - 8) * 255 // 56)))
    r, g, b = (ImageChops.darker(c, a) for c in src.crop(box).split())
    return Image.merge('RGBa', (r, g, b, a)).convert('RGBA')


def fit(im, w):
    return im.resize((w, round(w * im.height / im.width)), Image.LANCZOS)


def tile(fox, size, reach, shape=None):
    """The fox centred on size², the corners of its box `reach` of size from the centre.

    shape is the black under it: None for none, 'circle', or a corner radius as a share of size.
    """
    out = Image.new('RGBA', (size, size))
    if shape is not None:
        big = Image.new('L', (size * SS, size * SS))
        draw = ImageDraw.Draw(big)
        box = (0, 0, size * SS - 1, size * SS - 1)
        if shape == 'circle':
            draw.ellipse(box, fill=255)
        else:
            draw.rounded_rectangle(box, radius=size * SS * shape, fill=255)
        out.putalpha(big.resize((size, size), Image.LANCZOS))
    corner = (fox.width**2 + fox.height**2) ** 0.5 / 2
    f = fit(fox, round(fox.width * reach * size / corner))
    out.alpha_composite(f, ((size - f.width) // 2, (size - f.height) // 2))
    return out


def banner(fox, word):
    out = Image.new('RGBA', (320, 180), 'black')
    w = fit(word, 256)
    f = fit(fox, round(104 * fox.width / fox.height))
    top = (180 - f.height - 12 - w.height) // 2
    out.alpha_composite(f, ((320 - f.width) // 2, top))
    out.alpha_composite(w, ((320 - w.width) // 2, top + f.height + 12))
    return out.convert('RGB')


def vector(peak, box, colour):
    """The fox as a 24dp one-colour vector, 1dp clear around it."""
    # The median takes the scratches of the gold off its edges; without it the path is 20x longer.
    dark_fox = peak.crop(box).filter(ImageFilter.MedianFilter(7)).point(lambda v: 0 if v > 32 else 255)
    w, h = dark_fox.size
    side = max(w, h) * 24 / 22
    dx, dy = (side - w) / 2, (side - h) / 2

    def pt(p):
        return f'{p.x + dx:.0f},{p.y + dy:.0f}'

    d = []
    for curve in potrace.Bitmap(dark_fox).trace(turdsize=25, alphamax=0.6, opttolerance=1.0):
        d.append('M' + pt(curve.start_point))
        for s in curve:
            if s.is_corner:
                d.append(f'L{pt(s.c)}L{pt(s.end_point)}')
            else:
                d.append(f'C{pt(s.c1)} {pt(s.c2)} {pt(s.end_point)}')
        d.append('Z')
    return f'''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="{side:.1f}"
    android:viewportHeight="{side:.1f}">
    <path
        android:name="{MARK}"
        android:fillColor="{colour}"
        android:fillType="evenOdd"
        android:pathData="{''.join(d)}" />
</vector>
'''


def main():
    src = Image.open(SRC).convert('RGB')
    r, g, b = src.split()
    peak = ImageChops.lighter(ImageChops.lighter(r, g), b)
    fox_box, word_box = parts(peak.point(lambda v: 255 if v > LIT else 0))[:2]
    fox, word = cut(src, peak, fox_box), cut(src, peak, word_box)
    solid = fox.getchannel('A').point(lambda v: 255 if v == 255 else 0)
    gold = '#%02X%02X%02X' % tuple(round(c) for c in ImageStat.Stat(fox.convert('RGB'), solid).mean)

    for d, k in DENSITY.items():
        # Adaptive layers are 108dp; launchers may cut anything outside the middle 66dp circle.
        save(tile(fox, round(108 * k), 32 / 108), RES / f'drawable-{d}/ic_launcher_foreground.png')
        save(tile(fox, round(48 * k), 0.4, 0.2), RES / f'mipmap-{d}/ic_launcher.webp')
        save(tile(fox, round(48 * k), 0.38, 'circle'), RES / f'mipmap-{d}/ic_launcher_round.webp')
        save(tile(fox, round(80 * k), 0.4, 0), RES / f'mipmap-television-{d}/ic_launcher.webp')
    save(tile(fox, 512, 0.4, 0), ROOT / 'android/app/src/main/ic_launcher-playstore.png')
    save(tile(fox, 384, 0.4, 0), ROOT / 'assets/images/shikoo_mark.png')
    save(banner(fox, word), RES / 'mipmap-xhdpi/ic_banner.png')
    # Android draws small icons from their alpha alone; the gold shows where it doesn't (Files).
    (SERVICE / 'ic.xml').write_text(vector(peak, fox_box, '#FFFFFF'))
    (SERVICE / 'ic_service.xml').write_text(vector(peak, fox_box, gold))
    print('vectors in', SERVICE.relative_to(ROOT), 'gold', gold)


if __name__ == '__main__':
    main()
