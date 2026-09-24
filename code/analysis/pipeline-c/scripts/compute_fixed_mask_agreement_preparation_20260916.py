#!/usr/bin/env python3
"""Extend the published fixed-mask agreement tables with Arm C preparation maps."""
from __future__ import annotations

import json
from pathlib import Path

import nibabel as nib
import numpy as np
import pandas as pd
from scipy.stats import spearmanr

ROOT = Path("<DATA_ROOT>")
NORM = ROOT / "derivatives" / "contract-normalized"
MASK_PATH = NORM / "group-masks" / "D1-full_common_mask.nii"
STORED_AGGREGATE = ROOT / "logs" / "agreement_table_fixed_mask_fourdirection_20260910.tsv"
STORED_SUBJECT = ROOT / "logs" / "agreement_subject_rhos_fixed_mask_fourdirection_20260910.tsv"
AGGREGATE_OUTPUT = ROOT / "logs" / "agreement_table_fixed_mask_fourdirection_20260916.tsv"
SUBJECT_OUTPUT = ROOT / "logs" / "agreement_subject_rhos_fixed_mask_fourdirection_20260916.tsv"
PREPARATION_MODELS = {
    "MVPA_PreparePeriod_posneg90s",
    "MVPA_PreparePeriod_rotationVSmirror",
}
EXPECTED_AGGREGATE_ROWS = 66
EXPECTED_SUBJECT_ROWS = 1320
REPRODUCTION_TOLERANCE = 1e-12


def load_checked(path: Path, shape: tuple[int, ...], affine: np.ndarray) -> np.ndarray:
    if not path.is_file():
        raise FileNotFoundError(path)
    image = nib.load(path)
    if image.shape != shape:
        raise RuntimeError(f"Grid shape mismatch: {path}: {image.shape} != {shape}")
    delta = float(np.max(np.abs(image.affine - affine)))
    if delta >= 1e-5:
        raise RuntimeError(f"Grid affine mismatch: {path}: max delta={delta}")
    data = np.asarray(image.dataobj)
    if not np.isfinite(data).all():
        raise RuntimeError(f"Non-finite values: {path}")
    return data


def available_arms(model_dir: Path) -> list[str]:
    return sorted(path.name[4] for path in model_dir.glob("arm-?_mean.nii"))


def keyed(frame: pd.DataFrame, columns: list[str]) -> pd.DataFrame:
    return frame.set_index(columns).sort_index()


def main() -> None:
    for output in (AGGREGATE_OUTPUT, SUBJECT_OUTPUT):
        if output.exists():
            raise FileExistsError(f"Refusing to overwrite existing output: {output}")

    manifest = json.loads((ROOT / "docs" / "subject_manifest.json").read_text())
    cohorts = {
        "D1-full": [str(value).zfill(2) for value in manifest["D1_full"]["subjects"]],
        "D1-strict": [str(value).zfill(2) for value in manifest["D1_strict"]["subjects"]],
    }
    mask_image = nib.load(MASK_PATH)
    mask = np.asarray(mask_image.dataobj) > 0.5
    shape, affine = mask_image.shape, mask_image.affine
    n_voxels = int(mask.sum())
    if n_voxels != 158156:
        raise RuntimeError(f"Expected 158156 fixed-mask voxels, found {n_voxels}")

    aggregate_rows: list[dict] = []
    subject_rows: list[dict] = []
    for cohort, subjects in cohorts.items():
        model_dirs = sorted(path for path in (NORM / "group-models" / cohort).iterdir() if path.is_dir())
        for model_dir in model_dirs:
            model = model_dir.name
            arms = available_arms(model_dir)
            for first_index, first in enumerate(arms):
                for second in arms[first_index + 1:]:
                    pair = f"{first.upper()}-{second.upper()}"
                    first_group = load_checked(model_dir / f"arm-{first}_mean.nii", shape, affine)
                    second_group = load_checked(model_dir / f"arm-{second}_mean.nii", shape, affine)
                    rho_group = float(spearmanr(first_group[mask], second_group[mask]).statistic)
                    pair_subject_rhos = []
                    for subject in subjects:
                        first_path = NORM / f"arm-{first}" / model / f"sub-{subject}" / "s8wres_accuracy_minus_chance.nii"
                        second_path = NORM / f"arm-{second}" / model / f"sub-{subject}" / "s8wres_accuracy_minus_chance.nii"
                        first_subject = load_checked(first_path, shape, affine)
                        second_subject = load_checked(second_path, shape, affine)
                        rho_subject = float(spearmanr(first_subject[mask], second_subject[mask]).statistic)
                        pair_subject_rhos.append(rho_subject)
                        subject_rows.append({
                            "cohort": cohort, "model": model, "pair": pair,
                            "subject": f"sub-{subject}", "rho_subject": rho_subject,
                            "n_voxels": n_voxels,
                        })
                    aggregate_rows.append({
                        "cohort": cohort, "model": model, "pair": pair,
                        "rho_group": rho_group,
                        "rho_subject_mean": float(np.mean(pair_subject_rhos)),
                        "n_subjects": len(subjects), "n_voxels": n_voxels,
                    })

    aggregate = pd.DataFrame(aggregate_rows)
    subjects_table = pd.DataFrame(subject_rows)
    if len(aggregate) != EXPECTED_AGGREGATE_ROWS:
        raise RuntimeError(f"Expected {EXPECTED_AGGREGATE_ROWS} aggregate rows, found {len(aggregate)}")
    if len(subjects_table) != EXPECTED_SUBJECT_ROWS:
        raise RuntimeError(f"Expected {EXPECTED_SUBJECT_ROWS} subject rows, found {len(subjects_table)}")

    stored_aggregate = pd.read_csv(STORED_AGGREGATE, sep="\t")
    stored_subject = pd.read_csv(STORED_SUBJECT, sep="\t")
    if len(stored_aggregate) != 58 or len(stored_subject) != 1160:
        raise RuntimeError(f"Published input counts changed: aggregate={len(stored_aggregate)} subject={len(stored_subject)}")

    old_a = keyed(stored_aggregate, ["cohort", "model", "pair"])
    new_a = keyed(aggregate, ["cohort", "model", "pair"])
    missing_a = old_a.index.difference(new_a.index)
    if len(missing_a):
        raise RuntimeError(f"Missing published aggregate keys: {list(missing_a)}")
    aggregate_deltas = {
        column: float(np.max(np.abs(new_a.loc[old_a.index, column].to_numpy(dtype=float) - old_a[column].to_numpy(dtype=float))))
        for column in ["rho_group", "rho_subject_mean", "n_subjects", "n_voxels"]
    }

    old_s = keyed(stored_subject, ["cohort", "model", "pair", "subject"])
    new_s = keyed(subjects_table, ["cohort", "model", "pair", "subject"])
    missing_s = old_s.index.difference(new_s.index)
    if len(missing_s):
        raise RuntimeError(f"Missing published subject keys: {list(missing_s[:10])}")
    subject_deltas = {
        column: float(np.max(np.abs(new_s.loc[old_s.index, column].to_numpy(dtype=float) - old_s[column].to_numpy(dtype=float))))
        for column in ["rho_subject", "n_voxels"]
    }
    print(f"REPRODUCTION aggregate_rows=58 max_deltas={aggregate_deltas}")
    print(f"REPRODUCTION subject_rows=1160 max_deltas={subject_deltas}")
    if max(aggregate_deltas.values()) > REPRODUCTION_TOLERANCE or max(subject_deltas.values()) > REPRODUCTION_TOLERANCE:
        raise RuntimeError("Published agreement reproduction gate failed")

    new_rows = aggregate.loc[
        aggregate["model"].isin(PREPARATION_MODELS) & aggregate["pair"].isin(["A-C", "B-C"])
    ].sort_values(["model", "cohort", "pair"])
    if len(new_rows) != 8:
        raise RuntimeError(f"Expected 8 new preparation cells, found {len(new_rows)}")

    with AGGREGATE_OUTPUT.open("x", newline="") as stream:
        aggregate.to_csv(stream, sep="\t", index=False)
    with SUBJECT_OUTPUT.open("x", newline="") as stream:
        subjects_table.to_csv(stream, sep="\t", index=False)
    print(f"CREATED path={AGGREGATE_OUTPUT} rows={len(aggregate)}")
    print(f"CREATED path={SUBJECT_OUTPUT} rows={len(subjects_table)}")
    print("NEW_CELLS")
    print(new_rows.to_csv(sep="\t", index=False), end="")


if __name__ == "__main__":
    main()
