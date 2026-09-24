#!/usr/bin/env python3
"""Review-only Arm C preparation-period searchlights."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import nibabel as nib
import numpy as np
import pandas as pd
from nilearn.decoding import SearchLight
from nilearn.image import index_img
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

ROOT = Path("<DATA_ROOT>")
MODELS = (
    "MVPA_PreparePeriod_posneg90s",
    "MVPA_PreparePeriod_rotationVSmirror",
)


def binary_design(manifest: pd.DataFrame, first: str, second: str):
    selected = manifest.index[
        manifest["context"].isin([first, second])
    ].to_numpy(dtype=int)
    subset = manifest.loc[selected].reset_index(drop=True)
    if len(subset) != 10:
        raise RuntimeError(f"{first}/{second}: expected 10 samples, found {len(subset)}")
    labels = subset["context"].map({first: 0, second: 1}).to_numpy(dtype=int)
    first_blocks = sorted(subset.loc[subset["context"].eq(first), "block"])
    second_blocks = sorted(subset.loc[subset["context"].eq(second), "block"])
    if len(first_blocks) != 5 or len(second_blocks) != 5:
        raise RuntimeError("Expected five blocks per context")
    folds = []
    rows = []
    for fold, (first_block, second_block) in enumerate(
        zip(first_blocks, second_blocks), start=1
    ):
        test = subset.index[
            ((subset["context"] == first) & (subset["block"] == first_block))
            | ((subset["context"] == second) & (subset["block"] == second_block))
        ].to_numpy(dtype=int)
        train = subset.index[~subset.index.isin(test)].to_numpy(dtype=int)
        if len(train) != 8 or len(test) != 2 or set(train) & set(test):
            raise RuntimeError("Invalid leave-two-out fold")
        if np.bincount(labels[train], minlength=2).tolist() != [4, 4]:
            raise RuntimeError("Unbalanced training fold")
        if np.bincount(labels[test], minlength=2).tolist() != [1, 1]:
            raise RuntimeError("Unbalanced test fold")
        folds.append((train, test))
        for role, indices in (("train", train), ("test", test)):
            for index in indices:
                row = subset.iloc[index]
                rows.append({
                    "fold": fold,
                    "role": role,
                    "subset_index": int(index),
                    "source_index": int(selected[index]),
                    "context": row["context"],
                    "block": int(row["block"]),
                    "label": int(labels[index]),
                })
    return selected, labels, folds, rows


def run_component(series, manifest, mask, first, second, n_jobs):
    selected, labels, folds, rows = binary_design(manifest, first, second)
    component = index_img(series, selected.tolist())
    estimator = make_pipeline(StandardScaler(), SVC(kernel="linear", C=1.0))
    searchlight = SearchLight(
        mask_img=str(mask),
        process_mask_img=str(mask),
        radius=9.0,
        estimator=estimator,
        n_jobs=n_jobs,
        scoring="accuracy",
        cv=folds,
        verbose=0,
    )
    searchlight.fit(component, labels)
    return np.asarray(searchlight.scores_, dtype=np.float32), rows


def save_map(data, reference, path):
    image = nib.Nifti1Image(data.astype(np.float32), reference.affine, reference.header)
    image.set_data_dtype(np.float32)
    nib.save(image, path)


def main(subject: str, model: str, n_jobs: int) -> None:
    started = time.time()
    label = f"sub-{subject}"
    source = ROOT / "derivatives" / "arm-c" / "mvpa-preparation-refit" / label
    series_path = source / "preparation_betas.nii.gz"
    manifest_path = source / "preparation_manifest.tsv"
    mask = ROOT / "derivatives" / "common-searchlight-masks" / label / "arm-b_explicit_mask.nii"
    for path in (series_path, manifest_path, mask):
        if not path.is_file():
            raise FileNotFoundError(path)

    output = ROOT / "derivatives" / "arm-c" / "mvpa" / model / label
    if output.exists():
        raise FileExistsError(f"Refusing existing output: {output}")
    manifest = pd.read_csv(manifest_path, sep="\t")
    if len(manifest) != 15 or manifest.groupby("context").size().to_dict() != {
        "mirror": 5, "rotation+90": 5, "rotation-90": 5
    }:
        raise RuntimeError("Invalid preparation manifest")
    series = nib.load(series_path)
    reference = nib.load(mask)
    valid = np.asarray(reference.dataobj) > 0

    fold_rows = []
    if model == "MVPA_PreparePeriod_posneg90s":
        scores, rows = run_component(
            series, manifest, mask, "rotation+90", "rotation-90", n_jobs
        )
        for row in rows:
            row["component"] = "rotation+90_vs_rotation-90"
        fold_rows.extend(rows)
        n_folds = 5
        n_test_predictions = 10
        component_names = ["rotation+90_vs_rotation-90"]
        component_scores = []
    else:
        negative, negative_rows = run_component(
            series, manifest, mask, "rotation-90", "mirror", n_jobs
        )
        positive, positive_rows = run_component(
            series, manifest, mask, "rotation+90", "mirror", n_jobs
        )
        for row in negative_rows:
            row["component"] = "rotation-90_vs_mirror"
        for row in positive_rows:
            row["component"] = "rotation+90_vs_mirror"
        fold_rows.extend(negative_rows + positive_rows)
        scores = (negative + positive) / 2.0
        n_folds = 10
        n_test_predictions = 20
        component_names = ["rotation-90_vs_mirror", "rotation+90_vs_mirror"]
        component_scores = [negative, positive]

    if scores.shape != reference.shape or not np.isfinite(scores[valid]).all():
        raise RuntimeError("Invalid searchlight result")
    output.mkdir(parents=True, exist_ok=False)
    save_map(scores, reference, output / "accuracy.nii.gz")
    minus_chance = np.zeros_like(scores, dtype=np.float32)
    minus_chance[valid] = (scores[valid] - 0.5) * 100.0
    save_map(minus_chance, reference, output / "accuracy_minus_chance.nii.gz")
    if component_scores:
        save_map(component_scores[0], reference, output / "accuracy_rotation-neg90_vs_mirror.nii.gz")
        save_map(component_scores[1], reference, output / "accuracy_rotation-pos90_vs_mirror.nii.gz")
    pd.DataFrame(fold_rows).to_csv(
        output / "design_matrix.tsv", sep="\t", index=False
    )
    metadata = {
        "subject": subject,
        "model": model,
        "n_samples_in_beta_series": 15,
        "n_samples_used_per_binary_decoding": 10,
        "n_folds": n_folds,
        "fold_train_n": 8,
        "fold_test_n": 2,
        "n_test_predictions": n_test_predictions,
        "predicted_quantization_percentage_points": 100.0 / n_test_predictions,
        "chance": 0.5,
        "accuracy_minus_chance_unit": "percentage points",
        "radius_mm": 9.0,
        "scaling": "StandardScaler within training fold",
        "classifier": "SVC(kernel='linear', C=1.0)",
        "components": component_names,
        "component_combination": "arithmetic mean of two binary accuracy maps"
        if component_scores else "single binary accuracy map",
        "n_jobs": n_jobs,
        "runtime_seconds": time.time() - started,
    }
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2))
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--subject", required=True)
    parser.add_argument("--model", choices=MODELS, required=True)
    parser.add_argument("--n-jobs", type=int, default=12)
    args = parser.parse_args()
    main(str(args.subject).zfill(2), args.model, args.n_jobs)
