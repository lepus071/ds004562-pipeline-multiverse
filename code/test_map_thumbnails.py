"""Every map panel the page can show must have a file behind it.

The page offers four branches by two map types by three pipelines. A combination with no
file renders a placeholder, which is honest but easy to leave in by accident, so this pins
down which are expected to exist.

Run:  conda run -n py_analysis python test_map_thumbnails.py
"""
import json
import sys
from pathlib import Path

DOCS = Path("../ds004562-pipeline-multiverse/docs")
MAPS = DOCS / "maps"
ARMS = ["A", "B", "C"]
BRANCHES = ["visual_direction", "movement_direction", "task_context", "preparation_rotmirror"]
KINDS = ["t", "corrp"]
MIN_BYTES = 2_000


def main():
    bad = []
    index_path = MAPS / "index.json"
    if not index_path.exists():
        print(f"FAIL {index_path} is missing - run fetch_thumbnails.py")
        print("RESULT: FAIL")
        return 1
    index = json.loads(index_path.read_text(encoding="utf8"))

    expected = [f"{a}|{b}|{k}" for a in ARMS for b in BRANCHES for k in KINDS]
    for key in expected:
        entry = index.get(key)
        if entry is None:
            bad.append(f"{key}: no thumbnail, the page would show a placeholder")
            continue
        f = MAPS / entry["file"]
        if not f.exists():
            bad.append(f"{key}: {entry['file']} is listed but not on disk")
        elif f.stat().st_size < MIN_BYTES:
            bad.append(f"{key}: {entry['file']} is only {f.stat().st_size} bytes")
        if not str(entry.get("url", "")).startswith("https://neurovault.org/images/"):
            bad.append(f"{key}: does not link back to the archived map")

    extra = set(index) - set(expected)
    if extra:
        bad.append(f"thumbnails the page never shows: {sorted(extra)}")

    # the page has to reference the directory it was given
    page = (DOCS / "index.html").read_text(encoding="utf8")
    if 'src="maps/' not in page.replace("`", '"').replace("${entry.file}", ""):
        bad.append("index.html does not load anything from maps/")

    print(f"{len(index)} thumbnails indexed, {len(expected)} panels expected")
    for b in bad:
        print(f"FAIL {b}")
    if not bad:
        print("OK   every branch, map type and pipeline has an image that links back")
    print("RESULT:", "FAIL" if bad else "PASS")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
