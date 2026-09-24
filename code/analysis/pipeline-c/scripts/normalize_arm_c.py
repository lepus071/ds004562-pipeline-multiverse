#!/usr/bin/env python3
"""Normalize Arm C core maps to the frozen comparison grid and smooth 8 mm."""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import time
from pathlib import Path

import nibabel as nib
import numpy as np
from nilearn.image import smooth_img

ROOT = Path("<DATA_ROOT>")
NORM_ROOT = ROOT / "derivatives" / "contract-normalized"
REFERENCE = NORM_ROOT / "reference_spm_grid.nii"
ANTS = Path("<ANTS_ROOT>/bin/antsApplyTransforms")
TO_MNI6 = ROOT / ".templateflow" / "tpl-MNI152NLin6Asym" / "tpl-MNI152NLin6Asym_from-MNI152NLin2009cAsym_mode-image_xfm.h5"
BRANCHES = ["MVPA_VisualDirection_Alltask", "MVPA_MoveDirection_Alltasks"]


def subjects() -> list[str]:
    manifest = json.loads((ROOT / "docs" / "subject_manifest.json").read_text())
    return [str(s).zfill(2) for s in manifest["D1_full"]["subjects"]]


def finite_float32_copy(source: Path, destination: Path) -> None:
    image = nib.load(source)
    data = np.asarray(image.dataobj, dtype=np.float32)
    if not np.isfinite(data).all():
        data[~np.isfinite(data)] = 0
    output = nib.Nifti1Image(data, image.affine, image.header)
    output.set_data_dtype(np.float32)
    nib.save(output, destination)


def validate_grid(path: Path, reference: nib.spatialimages.SpatialImage) -> dict:
    image = nib.load(path)
    data = np.asarray(image.dataobj)
    result = {
        "shape": list(image.shape),
        "affine_max_delta": float(np.max(np.abs(image.affine - reference.affine))),
        "finite": bool(np.isfinite(data).all()),
        "min": float(np.min(data)),
        "max": float(np.max(data)),
    }
    if image.shape != reference.shape or result["affine_max_delta"] >= 1e-5 or not result["finite"]:
        raise RuntimeError(f"grid/QC failure for {path}: {result}")
    return result


def normalize_one(sub: str, branch: str) -> dict:
    label = f"sub-{sub}"
    source = ROOT / "derivatives" / "arm-c" / "mvpa" / branch / label / "accuracy_minus_chance.nii.gz"
    transform = ROOT / "derivatives" / "fmriprep-ds004562" / label / "ses-02fmri" / "anat" / f"{label}_ses-02fmri_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5"
    for required in (source, transform, REFERENCE, TO_MNI6, ANTS):
        if not required.is_file():
            raise FileNotFoundError(required)

    output_dir = NORM_ROOT / "arm-c" / branch / label
    output_dir.mkdir(parents=True, exist_ok=True)
    staged = output_dir / "res_accuracy_minus_chance.nii"
    normalized = output_dir / "wres_accuracy_minus_chance.nii"
    smoothed = output_dir / "s8wres_accuracy_minus_chance.nii"
    metadata = output_dir / "normalization.json"

    if not staged.exists():
        finite_float32_copy(source, staged)
    if not normalized.exists():
        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = ""
        command = [
            str(ANTS), "-d", "3", "-i", str(staged), "-r", str(REFERENCE),
            "-o", str(normalized), "-n", "BSpline[4]",
            "-t", str(TO_MNI6), "-t", str(transform),
        ]
        subprocess.run(command, check=True, env=env)
    reference = nib.load(REFERENCE)
    normalized_qc = validate_grid(normalized, reference)

    if not smoothed.exists():
        result = smooth_img(str(normalized), fwhm=8.0)
        result.set_data_dtype(np.float32)
        nib.save(result, smoothed)
    smoothed_qc = validate_grid(smoothed, reference)

    record = {
        "subject": sub,
        "branch": branch,
        "source": str(source),
        "normalization": "ANTs T1w-to-MNI152NLin2009cAsym then MNI152NLin6Asym-to-frozen-SPM-grid",
        "interpolation": "BSpline[4]",
        "smoothing_fwhm_mm": 8.0,
        "normalized": normalized_qc,
        "smoothed": smoothed_qc,
    }
    metadata.write_text(json.dumps(record, indent=2))
    return record


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--subject", default="all")
    parser.add_argument("--branch", choices=["all"] + BRANCHES, default="all")
    args = parser.parse_args()
    selected_subjects = subjects() if args.subject == "all" else [str(args.subject).zfill(2)]
    if any(s not in subjects() for s in selected_subjects):
        raise ValueError("subject is not in frozen D1-full")
    selected_branches = BRANCHES if args.branch == "all" else [args.branch]
    start = time.time()
    rows = []
    for sub in selected_subjects:
        for branch in selected_branches:
            rows.append(normalize_one(sub, branch))
            print(f"normalized sub-{sub} {branch}", flush=True)
    print(json.dumps({"maps": len(rows), "runtime_seconds": time.time() - start}, indent=2))


if __name__ == "__main__":
    main()
