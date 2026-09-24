#!/usr/bin/env python3
"""Review-only Arm C refit with an erasing-beta reproduction gate."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import h5py
import nibabel as nib
import numpy as np
import pandas as pd
from nilearn.glm.first_level import FirstLevelModel
from nilearn.image import concat_imgs
from scipy.io import loadmat

ROOT = Path("<DATA_ROOT>")
SCRIPT_DIR = ROOT / "scripts" / "arm_c"
sys.path.insert(0, str(SCRIPT_DIR))
from build_mvpa_glm import build_events, files  # noqa: E402

BUILD_SCRIPT = SCRIPT_DIR / "build_mvpa_glm.py"
EXPECTED_BUILD_SHA256 = "292a426d15941e3aea5b17f6f9124ef62f9912679d09bcc1ae7a8b11c2faba58"
REPRODUCTION_ROWS = tuple(range(60))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(
    subject: str,
    n_jobs: int,
    tolerance: float | None,
    dry_run: bool,
) -> None:
    started = time.time()
    label = f"sub-{subject}"
    if sha256(BUILD_SCRIPT) != EXPECTED_BUILD_SHA256:
        raise RuntimeError("build_mvpa_glm.py changed after Stage 2 review")
    if not dry_run and tolerance is None:
        raise ValueError("--max-abs-tolerance is required without --dry-run")
    if tolerance is not None and (tolerance < 0 or not np.isfinite(tolerance)):
        raise ValueError("--max-abs-tolerance must be finite and non-negative")

    prior = ROOT / "derivatives" / "arm-c" / "mvpa-glm-1stlevel" / label
    prior_complete = prior / "complete.json"
    prior_betas_path = prior / "condition_betas.nii.gz"
    prior_manifest_path = prior / "beta_manifest.tsv"
    for path in (prior_complete, prior_betas_path, prior_manifest_path):
        if not path.is_file():
            raise FileNotFoundError(path)

    prior_meta = json.loads(prior_complete.read_text())
    recorded_source_bold = Path(prior_meta["source_bold"])
    staged_bold, regfile, eventfile, mask = files(subject)
    bold = recorded_source_bold
    source_substituted = False
    if not bold.is_file():
        if bold.parent != Path("<SCRATCH_ROOT>/arm-c-bold-cache"):
            raise FileNotFoundError(bold)
        if not staged_bold.is_file():
            raise FileNotFoundError(staged_bold)
        bold = staged_bold
        source_substituted = True
    for path in (bold, regfile, eventfile, mask):
        if not path.is_file():
            raise FileNotFoundError(path)
    if str(mask) != prior_meta["explicit_mask"]:
        raise RuntimeError("Explicit mask differs from prior complete.json")

    with h5py.File(regfile, "r") as handle:
        confounds = np.column_stack([
            np.asarray(handle["move_cov"]).T,
            np.asarray(handle["move_derivative_cov"]).T,
            np.asarray(handle["R"]).T,
        ])
    if confounds.shape[0] != 1360 or not np.isfinite(confounds).all():
        raise RuntimeError(f"Invalid confounds: {confounds.shape}")
    confound_frame = pd.DataFrame(
        confounds,
        columns=[f"confound_{index:03d}" for index in range(confounds.shape[1])],
    )

    events, conditions = build_events(subject, eventfile)
    prior_manifest = pd.read_csv(prior_manifest_path, sep="\t")
    rebuilt_manifest = pd.DataFrame(conditions)
    if not rebuilt_manifest.equals(prior_manifest):
        raise RuntimeError("Rebuilt erasing manifest differs from stored manifest")

    model = FirstLevelModel(
        t_r=2.3,
        slice_time_ref=0.5,
        hrf_model="spm",
        drift_model="cosine",
        high_pass=1 / 128,
        noise_model="ar1",
        standardize=False,
        smoothing_fwhm=None,
        mask_img=str(mask),
        minimize_memory=True,
        verbose=0,
        n_jobs=n_jobs,
    )
    model.fit(
        str(bold),
        events=events[["onset", "duration", "trial_type"]],
        confounds=confound_frame,
    )

    prior_image = nib.load(prior_betas_path)
    prior_data = np.asarray(prior_image.dataobj)
    mask_data = np.asarray(nib.load(mask).dataobj) > 0
    gate_rows = []
    for volume_index in REPRODUCTION_ROWS:
        regressor = prior_manifest.iloc[volume_index]["regressor"]
        refit = model.compute_contrast(regressor, output_type="effect_size")
        refit_data = np.asarray(refit.dataobj, dtype=np.float32)
        stored_data = np.asarray(prior_data[..., volume_index], dtype=np.float32)
        stored_values = stored_data[mask_data]
        difference = np.abs(refit_data[mask_data] - stored_values)
        maximum = float(difference.max())
        stored_iqr = float(
            np.percentile(stored_values, 75)
            - np.percentile(stored_values, 25)
        )
        stored_max_abs = float(np.max(np.abs(stored_values)))
        gate_rows.append({
            "volume_index_zero_based": volume_index,
            "condition": regressor,
            "max_abs_difference": maximum,
            "stored_iqr": stored_iqr,
            "stored_max_abs": stored_max_abs,
            "tolerance": tolerance,
            "pass": None if tolerance is None else maximum <= tolerance,
        })
        print(json.dumps(gate_rows[-1]), flush=True)
    if dry_run:
        print(json.dumps({
            "dry_run": True,
            "subject": subject,
            "n_jobs": n_jobs,
            "output_written": False,
            "runtime_seconds": time.time() - started,
        }, indent=2))
        return
    if not all(row["pass"] for row in gate_rows):
        raise RuntimeError("Erasing-beta reproduction gate failed; no output written")

    raw = pd.read_csv(eventfile, sep="\t")
    preparation_rows = []
    preparation_images = []
    for block in range(1, 16):
        block_rows = raw.loc[raw["session_number"].eq(block)]
        context_values = block_rows["session_type"].unique()
        if len(context_values) != 1:
            raise RuntimeError(f"Block {block}: contexts={context_values}")
        start_rows = block_rows.loc[block_rows["trial_type"].eq("start_session")]
        if len(start_rows) != 1:
            raise RuntimeError(f"Block {block}: start rows={len(start_rows)}")
        regressor = f"nuis_start_b{block:02d}"
        if regressor not in model.design_matrices_[0].columns:
            raise RuntimeError(f"Missing design column: {regressor}")
        preparation_images.append(
            model.compute_contrast(regressor, output_type="effect_size")
        )
        event = start_rows.iloc[0]
        preparation_rows.append({
            "context": str(context_values[0]),
            "block": block,
            "regressor": regressor,
            "onset": float(event["onset"]),
            "duration": float(event["duration"]),
        })

    output = ROOT / "derivatives" / "arm-c" / "mvpa-preparation-refit" / label
    if output.exists():
        raise FileExistsError(f"Refusing existing output: {output}")
    output.mkdir(parents=True, exist_ok=False)

    series = concat_imgs(preparation_images, auto_resample=False)
    series.set_data_dtype(np.float32)
    nib.save(series, output / "preparation_betas.nii.gz")
    pd.DataFrame(preparation_rows).to_csv(
        output / "preparation_manifest.tsv", sep="\t", index=False
    )
    model.design_matrices_[0].to_csv(
        output / "design_matrix.tsv", sep="\t", index=False
    )
    pd.DataFrame(gate_rows).to_csv(
        output / "reproduction_gate.tsv", sep="\t", index=False
    )
    metadata = {
        "subject": subject,
        "recorded_source_bold": str(recorded_source_bold),
        "source_bold_used": str(bold),
        "source_substituted": source_substituted,
        "confound_file": str(regfile),
        "event_file": str(eventfile),
        "explicit_mask": str(mask),
        "n_confounds": int(confounds.shape[1]),
        "n_preparation_betas": 15,
        "nilearn_version": __import__("nilearn").__version__,
        "n_jobs": n_jobs,
        "max_abs_tolerance": tolerance,
        "runtime_seconds": time.time() - started,
        "build_mvpa_glm_sha256": EXPECTED_BUILD_SHA256,
    }
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2))
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--subject", required=True)
    parser.add_argument("--n-jobs", type=int, required=True)
    parser.add_argument("--max-abs-tolerance", type=float)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    main(
        str(args.subject).zfill(2),
        args.n_jobs,
        args.max_abs_tolerance,
        args.dry_run,
    )
