"""The uploader must describe every map correctly and must never leak the token.

Run:  conda run -n py_analysis python test_neurovault_upload.py
"""
import os
import sys
import tempfile
from pathlib import Path

import neurovault_upload as nv

NAMES = [
    "A__visual_direction__t.nii.gz",
    "A__visual_direction__corrp.nii.gz",
    "D__visual_direction__t.nii.gz",
]


def main():
    bad = []
    tmp = Path(tempfile.mkdtemp())
    for n in NAMES:
        (tmp / n).write_bytes(b"\x1f\x8b" + b"0" * 64)     # a stand-in, never uploaded here
    original = nv.MAPS
    nv.MAPS = tmp
    try:
        items = nv.maps_to_upload()
        by_name = {i["path"].name: i for i in items}

        t = by_name["A__visual_direction__t.nii.gz"]
        if "Pipeline A" not in t["name"] or "visual direction" not in t["name"]:
            bad.append(f"name does not identify pipeline and branch: {t['name']}")
        # the cohort is per pipeline: A ran all 22, D only the 21 shared participants
        if "n = 22" not in t["description"]:
            bad.append(f"pipeline A visual direction should be 22 participants: {t['description']}")
        if t["map_type"] != "T":
            bad.append(f"a t map should upload as map_type T, not {t['map_type']}")

        c = by_name["A__visual_direction__corrp.nii.gz"]
        if "TFCE" not in c["description"] or "5,000" not in c["description"]:
            bad.append("the corrected map does not say how it was corrected")
        if c["map_type"] != "IP":
            bad.append(f"a corrected 1-p map should upload as map_type IP, not {c['map_type']}")
        if c["name"] == t["name"]:
            bad.append("the t map and the corrected map would upload under the same name")

        # the partner laboratory's pipeline must not go out by default
        if "D__visual_direction__t.nii.gz" in by_name:
            bad.append("pipeline D was included without being asked for")
        if len(items) != len(NAMES) - 1:
            bad.append(f"{len(items)} maps kept, expected {len(NAMES) - 1} with D withheld")

        opted_in = {i["path"].name: i for i in nv.maps_to_upload(include_withheld=True)}
        d = opted_in.get("D__visual_direction__t.nii.gz")
        if d is None:
            bad.append("--include-d does not bring pipeline D back")
        else:
            if "independent laboratory" not in d["description"]:
                bad.append("pipeline D is not identified as the partner lab's analysis")
            if "n = 21" not in d["description"]:
                bad.append(f"pipeline D visual direction should be 21 participants: {d['description']}")

        # the collection must not describe maps it does not contain
        if "Pipeline D is a second laboratory" in nv.COLLECTION["description"]:
            bad.append("the collection description still claims pipeline D is included")
        if "not included in this collection" not in nv.COLLECTION["description"]:
            bad.append("the collection description does not say the fourth pipeline is absent")

        # a file that does not carry pipeline, branch and kind must stop the run
        (tmp / "stray.nii.gz").write_bytes(b"\x1f\x8b")
        try:
            nv.maps_to_upload()
            bad.append("an unnamed map was accepted instead of stopping the run")
        except SystemExit:
            pass
        (tmp / "stray.nii.gz").unlink()

        # the token must come from the environment only
        src = Path(nv.__file__).read_text(encoding="utf8")
        if "NEUROVAULT_TOKEN" not in src:
            bad.append("the token is not read from the environment")
        # the token may be read and sent, never printed, parsed from argv, or written down
        import re
        leaks = [
            (r"print\([^)]*token", "printed"),
            (r"--token", "taken as a command-line flag"),
            (r"add_argument\([^)]*token", "taken as a command-line flag"),
            (r"(write|dump|save)[^\n]*token", "written to disk"),
        ]
        for pattern, why in leaks:
            if re.search(pattern, src, re.I):
                bad.append(f"the token could be {why}")
        # public by necessity: the API cannot serve a private collection. The guard that
        # matters is therefore what goes in it, not the flag.
        if nv.WITHHELD != {"D"}:
            bad.append(f"the withheld set changed to {nv.WITHHELD}")
    finally:
        nv.MAPS = original

    if not bad:
        print("OK   pipeline D withheld by default, maps described, "
              "token from the environment")
    for b in bad:
        print(f"FAIL {b}")
    print("RESULT:", "FAIL" if bad else "PASS")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
