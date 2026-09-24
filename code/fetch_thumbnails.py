"""Pull the glass-brain thumbnails NeuroVault generated for our maps.

They are the only rendering of the maps that works everywhere, including on a phone, and
NeuroVault's own 3D view is currently unavailable for this collection. Copying them into the
repository means the results page shows brains without depending on another site staying up.

Run:  conda run -n py_analysis python fetch_thumbnails.py
"""
import json
import sys
from pathlib import Path

import requests

COLLECTION = 24567
OUT = Path("../ds004562-pipeline-multiverse/docs/maps")
API = f"https://neurovault.org/api/collections/{COLLECTION}/images/?limit=100"


def key_from(image):
    """A__visual_direction__t.nii.gz -> ('A', 'visual_direction', 't')."""
    stem = Path(image["file"]).name.replace(".nii.gz", "")
    parts = stem.split("__")
    if len(parts) != 3:
        raise SystemExit(f"unexpected file name on image {image['id']}: {stem}")
    return tuple(parts)


def main():
    r = requests.get(API, timeout=60)
    r.raise_for_status()
    images = r.json()["results"]
    OUT.mkdir(parents=True, exist_ok=True)

    index, missing = {}, []
    for im in images:
        arm, branch, kind = key_from(im)
        thumb = im.get("thumbnail")
        if not thumb:
            missing.append(im["id"])
            continue
        name = f"{arm}__{branch}__{kind}.jpg"
        body = requests.get(thumb, timeout=60)
        body.raise_for_status()
        (OUT / name).write_bytes(body.content)
        index[f"{arm}|{branch}|{kind}"] = {
            "file": name,
            "image": im["id"],
            "url": f"https://neurovault.org/images/{im['id']}/",
        }

    (OUT / "index.json").write_text(json.dumps(index, indent=1, sort_keys=True), encoding="utf8")
    total = sum((OUT / v["file"]).stat().st_size for v in index.values())
    print(f"{len(index)} thumbnails, {total / 1024:.0f} KB, in {OUT}")
    if missing:
        print(f"no thumbnail yet for images: {missing}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
