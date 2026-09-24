"""Split the server brain figures into their t-map and accuracy blocks."""
from pathlib import Path

import numpy as np
from PIL import Image

FIG = Path("figures")
SRV = Path("from_server")


def block_band(im):
    """Rows of the blank band that separates block A (t maps) from block B (accuracy).

    The server figures stack the two blocks with a white gutter between them; finding it
    is safer than a hard-coded fraction, which used to cut 134 px into pipeline D's brains.
    """
    a = np.asarray(im.convert("L"))
    h = a.shape[0]
    white = (a > 250).all(axis=1)
    runs, start = [], None
    for i, w in enumerate(white):
        if w and start is None:
            start = i
        elif not w and start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, h))
    mid = [r for r in runs if 0.25 * h < (r[0] + r[1]) / 2 < 0.75 * h]
    if not mid:
        raise SystemExit("no blank band found between the two blocks")
    return max(mid, key=lambda r: r[1] - r[0])


def caption_rows(a, gutter_top, left=900, max_height=120):
    """Rows of the "Block B" caption, which sits level with the last row of block A.

    No horizontal cut can separate it from the brains beside it, so it is painted out
    after the crop instead.
    """
    ink = (a[:, :left] < 250).any(axis=1)
    i = gutter_top - 1
    if i < 0 or not ink[i]:
        return None
    while i >= 0 and ink[i]:
        i -= 1
    start, end = i + 1, gutter_top
    return (start, end) if end - start <= max_height else None


def crop_hero(stem="song_fig8_context"):
    """Split a server figure into its t-map block and its accuracy block."""
    src = SRV / f"{stem}.png"
    dst = FIG / f"{stem}_tfce.png"
    if src.exists():
        im = Image.open(src)
        w, h = im.size
        top, bot = block_band(im)
        block_a = im.crop((0, 0, w, top))
        cap = caption_rows(np.asarray(im.convert("L")), top)
        if cap:
            pad = 6            # the caption's descenders reach past the detected run
            box = (1000, cap[1] - cap[0] + pad)
            block_a.paste(Image.new(block_a.mode, box, "white"), (0, cap[0] - pad))
        block_a.save(dst)
        im.crop((0, bot, w, h)).save(FIG / f"{stem}_accuracy.png")
    return dst
