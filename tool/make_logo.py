"""Draws the app's logo: a hammer and a wrench crossed, on the brand blue.

    python tool/make_logo.py

Writes into assets/branding/:
  icon.png        1024x1024, rounded square, full artwork (old Android, web)
  foreground.png  1024x1024, tools only on transparent, kept inside the safe
                  zone (Android adaptive icons)
  background.png  1024x1024, the blue gradient (Android adaptive icons)
  logo.png        512x512, same as icon.png (shown inside the app)
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SS = 4  # draw 4x bigger, then shrink: smooth edges
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'branding')

TOP = (25, 118, 210)      # #1976D2
BOTTOM = (10, 62, 150)    # #0A3E96
STEEL = (240, 244, 248)
WRENCH = (255, 255, 255)
WOOD = (255, 179, 0)      # amber
WOOD_DARK = (230, 140, 0)


def gradient(size):
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        row = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = row
    return img


def rounded_mask(size, radius):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def hammer(s):
    """Upright hammer, centred on a transparent s x s layer."""
    layer = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = s / 2
    # handle
    hw = 0.075 * s
    d.rounded_rectangle([cx - hw / 2, 0.30 * s, cx + hw / 2, 0.84 * s], radius=hw / 2, fill=WOOD)
    d.rounded_rectangle([cx + hw * 0.08, 0.30 * s, cx + hw / 2, 0.84 * s], radius=hw / 4, fill=WOOD_DARK)
    # head: a block with a flat striking face on the right and a taper on the left
    y1, y2 = 0.17 * s, 0.31 * s
    d.polygon(
        [
            (cx - 0.20 * s, y1 + 0.035 * s), (cx - 0.16 * s, y1), (cx + 0.13 * s, y1),
            (cx + 0.17 * s, y1 - 0.01 * s), (cx + 0.17 * s, y2 + 0.01 * s), (cx + 0.13 * s, y2),
            (cx - 0.16 * s, y2), (cx - 0.20 * s, y2 - 0.035 * s),
        ],
        fill=STEEL,
    )
    d.rectangle([cx + 0.13 * s, y1 - 0.01 * s, cx + 0.17 * s, y2 + 0.01 * s], fill=(205, 214, 224))
    return layer


def wrench(s):
    """Upright open-end wrench, centred on a transparent s x s layer."""
    layer = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = s / 2
    hw = 0.085 * s
    # handle with a hanging hole at the bottom
    d.rounded_rectangle([cx - hw / 2, 0.30 * s, cx + hw / 2, 0.84 * s], radius=hw / 2, fill=WRENCH)
    d.ellipse([cx - 0.018 * s, 0.795 * s, cx + 0.018 * s, 0.83 * s], fill=(0, 0, 0, 0))
    # head: a ring...
    r = 0.135 * s
    cy = 0.24 * s
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WRENCH)
    # ...with a mouth cut into the top (transparent) that fits a nut
    mw = 0.085 * s
    d.polygon(
        [(cx - mw / 2, cy - r - 0.02 * s), (cx + mw / 2, cy - r - 0.02 * s), (cx + mw / 2, cy + 0.01 * s), (cx - mw / 2, cy + 0.01 * s)],
        fill=(0, 0, 0, 0),
    )
    d.ellipse([cx - mw / 2, cy - 0.005 * s, cx + mw / 2, cy + 0.045 * s], fill=(0, 0, 0, 0))
    return layer


def tools(size, scale):
    """Both tools crossed, as one transparent size x size layer."""
    s = size * SS
    art = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    for layer, angle in ((wrench(s), 38), (hammer(s), -38)):
        art.alpha_composite(layer.rotate(angle, resample=Image.BICUBIC, center=(s / 2, s / 2)))
    # a soft shadow under the artwork, for depth
    shadow = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    shadow.putalpha(art.getchannel('A').point(lambda a: int(a * 0.28)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s * 0.012))
    offset = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    offset.paste(shadow, (0, round(s * 0.012)))
    composed = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    composed.alpha_composite(offset)
    composed.alpha_composite(art)
    if scale != 1:
        inner = round(s * scale)
        composed = composed.resize((inner, inner), Image.LANCZOS)
        canvas = Image.new('RGBA', (s, s), (0, 0, 0, 0))
        canvas.alpha_composite(composed, ((s - inner) // 2, (s - inner) // 2))
        composed = canvas
    return composed.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    size = 1024

    # adaptive: background and foreground are separate layers
    gradient(size).save(os.path.join(OUT, 'background.png'))
    tools(size, 0.64).save(os.path.join(OUT, 'foreground.png'))  # inside the 66% safe zone

    # full icon: rounded square with the artwork
    icon = gradient(size).convert('RGBA')
    icon.alpha_composite(tools(size, 0.86))
    icon.putalpha(rounded_mask(size, round(size * 0.22)))
    icon.save(os.path.join(OUT, 'icon.png'))
    icon.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, 'logo.png'))
    print('written to', os.path.normpath(OUT))


if __name__ == '__main__':
    main()
