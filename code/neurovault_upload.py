"""Upload the group statistical maps to a NeuroVault collection.

The token is read from the environment, never from a file and never from the command line,
so it cannot end up in a shell history or a commit:

    $env:NEUROVAULT_TOKEN = "..."      # PowerShell, this session only
    conda run -n py_analysis python neurovault_upload.py --dry-run
    conda run -n py_analysis python neurovault_upload.py

The collection is created public, because NeuroVault's API cannot serve a private one: its
numeric id answers 403 and its private slug answers 500, while public collections work
normally. Only material we have already published elsewhere goes in it.

Pipeline D belongs to the partner laboratory. It is excluded unless --include-d is passed,
and passing it is a statement that they have agreed to publication.
"""
import argparse
import os
import sys
from pathlib import Path

import requests

API = "https://neurovault.org/api"
MAPS = Path("from_server/maps")

COLLECTION = {
    # the first attempt reserved the earlier name on a collection that NeuroVault then could
    # not serve at all; that record is unusable and cannot be deleted through the API
    "name": "Decoding the brain, or decoding the pipeline? Analysis pipelines on ds004562",
    "description": (
        "Group-level decoding maps from four independent analysis pipelines applied to the same "
        "dataset (OpenNeuro ds004562; Song, Shin, Kim & Jeong, 2023, Front. Hum. Neurosci. 17, "
        "1221944). Pipelines A, B and C implement the original decoding design and differ only in "
        "software: A is the original authors' SPM/TDT toolchain, B swaps preprocessing for "
        "fMRIPrep, C additionally swaps the first-level model and classifier for Nilearn and "
        "scikit-learn. A fourth pipeline, a second laboratory's independent analysis of the same "
        "dataset, is part of the study but is not included in this collection. All maps here are "
        "masked to one frozen common mask of 158,156 voxels and were tested with TFCE, 5,000 "
        "permutations."
    ),
    "full_dataset_url": "https://github.com/lepus071/ds004562-pipeline-multiverse",
    "private": False,
}

PIPELINE = {
    "A": "A - the original authors' toolchain (SPM12/CONN/ART, SPM GLM, The Decoding Toolbox)",
    "B": "B - preprocessing swapped (fMRIPrep/FastSurfer, SPM GLM, TDT)",
    "C": "C - downstream software swapped as well (fMRIPrep, Nilearn GLM, scikit-learn SVC)",
    "D": "D - an independent laboratory (SPM12, NeuroElf GLM, CoSMoMVPA/LIBSVM)",
}
SLUG = {"visual_direction": "visual direction", "movement_direction": "movement direction",
        "task_context": "task context −90/+90", "preparation_rotmirror": "preparation rotation/mirror"}
SUMMARY = Path("from_server/summary_frozenmask_20260922.tsv")

# the cohort is per pipeline and branch, not per branch: pipeline D ran on the shared
# participants only, so it is read from the summary the maps came with
def cohorts():
    import csv
    with open(SUMMARY, newline="", encoding="utf8") as f:
        return {(r["arm"], r["branch"]): int(r["n_subjects"]) for r in csv.DictReader(f, delimiter="	")}


# randomise writes a t map and a corrected 1-p map; NeuroVault has a map type for each
MAP_TYPE = {"t": "T", "corrp": "IP"}

# the partner laboratory's pipeline: never uploaded unless explicitly asked for
WITHHELD = {"D"}

COMMON = {
    "modality": "fMRI-BOLD",
    "analysis_level": "G",
    "is_valid": True,
    "target_template_image": "GenericMNI",
    "smoothness_fwhm": 8,
    # statistic_parameters is a numeric field on NeuroVault, not free text; how the statistic
    # was produced belongs in each map's description instead
}


def maps_to_upload(include_withheld=False):
    """Every map under from_server/maps, named <pipeline>__<branch>__<kind>.nii.gz.

    Pipeline D is left out unless the caller says otherwise.
    """
    n_by = cohorts() if SUMMARY.exists() else {}
    out, skipped = [], []
    for path in sorted(MAPS.glob("*.nii.gz")):
        parts = path.name.replace(".nii.gz", "").split("__")
        if len(parts) != 3:
            raise SystemExit(f"cannot read pipeline/branch/kind from {path.name}")
        arm, slug, kind = parts
        if kind not in MAP_TYPE:
            raise SystemExit(f"unknown map kind {kind!r} in {path.name}")
        if arm in WITHHELD and not include_withheld:
            skipped.append(path.name)
            continue
        branch = SLUG.get(slug, slug.replace("_", " "))
        n = n_by.get((arm, branch))
        out.append({
            "path": path,
            "arm": arm,
            "branch": branch,
            "kind": kind,
            "map_type": MAP_TYPE[kind],
            "name": f"Pipeline {arm} - {branch} - {'TFCE-corrected 1-p' if kind == 'corrp' else 'group t'}",
            "description": (
                f"Pipeline {PIPELINE[arm]}. Branch: {branch}. "
                + (f"n = {n} participants. " if n else "")
                + ("Corrected 1-p from TFCE, 5,000 permutations. "
                   if kind == "corrp" else "Group t map from a one-sample t across participants. ")
                + "Masked to the frozen common mask of 158,156 voxels shared by all four pipelines."
            ),
        })
    if skipped:
        print(f"withheld: {len(skipped)} maps from pipeline "
              f"{', '.join(sorted(WITHHELD))} are not being uploaded")
    return out


def collection_key(session, cid):
    """How the API addresses this collection.

    A private collection is not reachable by its numeric id - that answers 403 even for its
    owner. It is addressed by the slug in its own url, the same secret that appears in the
    shareable link.
    """
    r = session.get(f"{API}/my_collections/", timeout=60)
    r.raise_for_status()
    for c in r.json().get("results", []):
        if c.get("id") == cid:
            slug = c.get("url", "").rstrip("/").rsplit("/", 1)[-1]
            return slug or str(cid)
    return str(cid)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="list what would be uploaded, contact nothing")
    ap.add_argument("--collection", type=int, help="upload into an existing collection id")
    ap.add_argument("--include-d", action="store_true",
                    help="also upload the partner laboratory's pipeline; only with their agreement")
    args = ap.parse_args()

    items = maps_to_upload(include_withheld=args.include_d)
    if not items:
        raise SystemExit(f"no maps found in {MAPS}/ - fetch them first")

    print(f"{len(items)} maps to upload:")
    for it in items:
        size = it["path"].stat().st_size / 1e6
        print(f"  {it['name']:<62} {size:5.1f} MB")
    if args.dry_run:
        print("\ndry run: nothing was sent")
        return 0

    token = os.environ.get("NEUROVAULT_TOKEN")
    if not token:
        raise SystemExit("set NEUROVAULT_TOKEN in the environment first")
    session = requests.Session()

    # NeuroVault is a Django REST app; installations differ on whether the token header reads
    # "Bearer" or "Token", and guessing wrong is a bare 401. Try both on a request that
    # changes nothing.
    scheme, probe = None, None
    for candidate in ("Bearer", "Token"):
        probe = session.get(f"{API}/my_collections/",
                            headers={"Authorization": f"{candidate} {token}"}, timeout=60)
        if probe.status_code < 400:
            scheme = candidate
            break
    if scheme is None:
        raise SystemExit(f"the token was not accepted as Bearer or Token "
                         f"({probe.status_code if probe else 'no response'}); "
                         "check it was copied whole and is still valid")
    session.headers["Authorization"] = f"{scheme} {token}"
    print(f"authenticated with the {scheme} scheme")

    cid = args.collection
    if cid is None:
        r = session.post(f"{API}/collections/", data=COLLECTION, timeout=60)
        if r.status_code >= 400:
            hint = ("\n  a collection with this name already exists: pass --collection <id> "
                    "to add to it" if "already exists" in r.text else "")
            raise SystemExit(f"could not create the collection: {r.status_code} {r.text[:300]}{hint}")
        cid = r.json()["id"]
        print(f"created collection {cid}")

    key = collection_key(session, cid)
    if key != str(cid):
        print(f"addressing it as {key} (its private slug)")

    for it in items:
        # images are posted to their collection, not to the images root: /api/images/ is
        # read-only and answers 405
        payload = dict(COMMON, name=it["name"], description=it["description"],
                       map_type=it["map_type"])
        payload = {k: v for k, v in payload.items() if v is not None}
        with open(it["path"], "rb") as fh:
            r = session.post(f"{API}/collections/{key}/images/", data=payload,
                             files={"file": fh}, timeout=300)
        if r.status_code >= 400:
            print(f"FAILED {it['name']}: {r.status_code} {r.text[:200]}")
            return 1
        print(f"uploaded {it['name']} -> image {r.json()['id']}")

    print(f"\nhttps://neurovault.org/collections/{cid}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
