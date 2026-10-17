#!/usr/bin/env python3
# /// script
# requires-python = "==3.12.*"
# dependencies = ["pillow==12.3.0", "potracer==0.0.4"]
# ///
"""Writes every Shikoo brand image from one source, assets/brand/logo-source.jpg.

The source is a gold mark on pure black: the fox on top, the word SHIKOONET under it, then a thin
line, which is left out. To change the brand, replace that file and run from the repository root:

    source ~/android-toolchain/env.sh && uv run tools/shikoo-brand.py

It overwrites the launcher, round, TV and Play icons, the adaptive foreground (also the Android 12+
splash icon), the TV banner, the notification and quick-settings icon, the in-app mark, and the
Windows app and tray icons. Each file carries MARK, which test/shikoo/brand_test.dart looks for.
"""

import io
import struct
import sys
from pathlib import Path

import potrace
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps, ImageStat, PngImagePlugin

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'assets/brand/logo-source.jpg'
RES = ROOT / 'android/app/src/main/res'
SERVICE = ROOT / 'android/service/src/main/res/drawable'
MARK = 'shikoo-brand'
DENSITY = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
LIT = 40  # the darkest channel value still counted as the mark, for finding its parts
SS = 4  # supersampling for the drawn shapes' edges
ICO = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)  # FlClash's icoSizes; the tray stops at 64
WINDOWS = ROOT / 'windows/runner/resources/app_icon.ico'
TRAY = ROOT / 'assets/images/tray/windows'


def png(im):
    info = PngImagePlugin.PngInfo()
    info.add_text('Software', MARK)
    out = io.BytesIO()
    im.save(out, 'PNG', pnginfo=info, optimize=True)
    return out.getvalue()


def save(im, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == '.webp':
        im.save(path, lossless=True, xmp=MARK.encode())
    else:
        path.write_bytes(png(im))
    print(path.relative_to(ROOT), im.size)


def ico(frames, path):
    """One PNG frame per size, as FlClash's tool/src/icons/ico.dart writes them."""
    data = [png(im) for im in frames]
    head = struct.pack('<3H', 0, 1, len(data))
    at = len(head) + 16 * len(data)
    for im, d in zip(frames, data):
        head += struct.pack('<4B2H2I', im.width % 256, im.height % 256, 0, 0, 1, 32, len(d), at)
        at += len(d)
    path.write_bytes(head + b''.join(data))
    print(path.relative_to(ROOT), [im.width for im in frames])


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
    # A shade off black: a pure black card has no edge on the TV launcher's black page.
    out = Image.new('RGBA', (320, 180), '#1A1A1A')
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
    w, h = src.size
    if max(peak.getpixel(c) for c in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))) > LIT:
        sys.exit(f'{SRC}: the background must be pure black, or the fox is traced as the whole frame')
    found = parts(peak.point(lambda v: 255 if v > LIT else 0))
    if len(found) < 2:
        sys.exit(f'{SRC}: expected the fox, then the word mark under it, on black')
    fox_box, word_box = found[:2]
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
    ico([tile(fox, s, 0.4, 0.2) for s in ICO], WINDOWS)
    # The tray: a grey fox while off; on, through the system proxy (2) or TUN (3), the gold one.
    grey = Image.merge('RGBA', (*[ImageOps.grayscale(fox)] * 3, fox.getchannel('A')))
    for n, f in ((1, grey), (2, fox), (3, fox)):
        ico([tile(f, s, 0.46, 'circle') for s in ICO if s <= 64], TRAY / f'status_{n}.ico')
    # Android draws small icons from their alpha alone; the gold shows where it doesn't (Files).
    (SERVICE / 'ic.xml').write_text(vector(peak, fox_box, '#FFFFFF'))
    (SERVICE / 'ic_service.xml').write_text(vector(peak, fox_box, gold))
    print('vectors in', SERVICE.relative_to(ROOT), 'gold', gold)


if __name__ == '__main__':
    main()
