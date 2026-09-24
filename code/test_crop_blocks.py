"""The block split must land in the blank gutter, never through a row of brains.

Run:  conda run -n py_analysis python test_crop_blocks.py
"""
import sys

import numpy as np
from PIL import Image

from figure_blocks import FIG, SRV, block_band

STEMS = ("song_fig6_visual", "song_fig7_movement", "song_fig8_context", "song_fig9_prep_rotmirror")
OLD_FRACTION = 0.472          # the hard-coded split this test was written against


def ink_rows(im):
    a = np.asarray(im.convert("L"))
    return ~(a > 250).all(axis=1)


def main(fraction=None):
    bad = []
    for stem in STEMS:
        src = SRV / f"{stem}.png"
        if not src.exists():
            print(f"SKIP {stem}: no source")
            continue
        im = Image.open(src)
        h = im.size[1]
        band_top, band_bot = block_band(im)          # the true blank gutter
        cut = int(h * fraction) if fraction is not None else band_top
        if not band_top <= cut <= band_bot:
            lost = int(ink_rows(im)[min(cut, band_top):max(cut, band_top)].sum())
            bad.append(f"{stem}: cut at row {cut} ({cut / h:.4f}) misses the gutter "
                       f"{band_top}-{band_bot} and drops {lost} rows of content")
        else:
            print(f"OK   {stem}: cut at row {cut} ({cut / h:.4f}) inside gutter {band_top}-{band_bot}")
        out = FIG / f"{stem}_tfce.png"
        if out.exists():
            # the "Block B" caption must not survive in the block A crop
            tail = np.asarray(Image.open(out).convert("L"))[-80:, :1000]
            if (tail < 250).any():
                bad.append(f"{stem}: block A crop still carries the Block B caption")
    for b in bad:
        print(f"FAIL {b}")
    print("RESULT:", "FAIL" if bad else "PASS")
    return 1 if bad else 0


if __name__ == "__main__":
    frac = OLD_FRACTION if "--old" in sys.argv else None
    sys.exit(main(frac))
