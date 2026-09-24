#!/usr/bin/env python3
"""Review-only proposal for Arm C's five currently runnable remaining models."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import nibabel as nib
import numpy as np
import pandas as pd
from nilearn.decoding import SearchLight
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

from run_context_searchlight_branch3_final_20260909 import (
    BRANCHES as CONTEXT_PAIRS,
    condition_indices,
)

ROOT = Path("<DATA_ROOT>")

NONCV_CONTEXT_MODELS = {
    "MVPA_TaskContext_posneg90s":
        "MVPA_TaskContext_CV_posneg90s",
    "MVPA_TaskContext_rotationVSmirror":
        "MVPA_TaskContext_CV_rotationVSmirror",
}

FOUR_DIRECTION_MODELS = {
    "MVPA_FourDirection_rot_neg90": "rotation-90",
    "MVPA_FourDirection_rot_pos90": "rotation+90",
    "MVPA_FourDirection_mirror": "mirror",
}

ALL_MODELS = (
    list(NONCV_CONTEXT_MODELS)
    + list(FOUR_DIRECTION_MODELS)
)


def build_noncv_context_design(
    manifest: pd.DataFrame,
    model: str,
) -> tuple[np.ndarray, list[tuple[np.ndarray, np.ndarray]], float, str]:
    source_branch = NONCV_CONTEXT_MODELS[model]
    context_labels = {
        "rotation+90": 0,
        "rotation-90": 1,
        "mirror": 2,
    }
    y = manifest["context"].map(context_labels).to_numpy(dtype=int)
    if np.any(pd.isna(manifest["context"].map(context_labels))):
        raise RuntimeError("Unknown context in beta manifest")

    folds = []
    for train_first, train_second, test_first, test_second in (
        CONTEXT_PAIRS[source_branch]
    ):
        train = np.concatenate([
            condition_indices(manifest, *train_first),
            condition_indices(manifest, *train_second),
        ])
        test = np.concatenate([
            condition_indices(manifest, *test_first),
            condition_indices(manifest, *test_second),
        ])

        if len(train) != 10 or len(test) != 10:
            raise RuntimeError("Unexpected non-CV train/test sample count")
        if set(train) & set(test):
            raise RuntimeError("Non-CV train/test sample indices overlap")
        if set(y[train]) != set(y[test]) or len(set(y[train])) != 2:
            raise RuntimeError("Non-CV fold is not balanced binary decoding")
        if not all(np.sum(y[train] == label) == 5 for label in set(y[train])):
            raise RuntimeError("Non-CV training classes are unbalanced")
        if not all(np.sum(y[test] == label) == 5 for label in set(y[test])):
            raise RuntimeError("Non-CV test classes are unbalanced")

        folds.append((train, test))

    expected_folds = 8 if model == "MVPA_TaskContext_posneg90s" else 16
    if len(folds) != expected_folds:
        raise RuntimeError(
            f"Expected {expected_folds} non-CV folds, found {len(folds)}"
        )

    return (
        y,
        folds,
        0.5,
        "Song Step3_mvpa07 custom train/test pairs without CV subdivision",
    )


def build_four_direction_design(
    manifest: pd.DataFrame,
    model: str,
) -> tuple[np.ndarray, list[tuple[np.ndarray, np.ndarray]], float, str]:
    context = FOUR_DIRECTION_MODELS[model]
    direction_labels = {
        "leftward": 0,
        "rightward": 1,
        "upward": 2,
        "downward": 3,
    }
    y = manifest["direction"].map(direction_labels).to_numpy(dtype=int)
    if np.any(pd.isna(manifest["direction"].map(direction_labels))):
        raise RuntimeError("Unknown direction in beta manifest")

    selected = manifest.index[
        manifest["context"].eq(context)
    ].to_numpy(dtype=int)
    if len(selected) != 20:
        raise RuntimeError(
            f"Expected 20 estimates for {context}, found {len(selected)}"
        )

    block_values = sorted(manifest.iloc[selected]["block"].unique())
    if len(block_values) != 5:
        raise RuntimeError(
            f"Expected five blocks for {context}, found {block_values}"
        )

    folds = []
    for held_block in block_values:
        test = selected[
            manifest.iloc[selected]["block"].to_numpy() == held_block
        ]
        train = selected[
            manifest.iloc[selected]["block"].to_numpy() != held_block
        ]

        if len(train) != 16 or len(test) != 4:
            raise RuntimeError("Unexpected four-direction sample count")
        if set(train) & set(test):
            raise RuntimeError("Four-direction train/test samples overlap")
        if set(y[train]) != {0, 1, 2, 3}:
            raise RuntimeError("Training set does not contain four directions")
        if set(y[test]) != {0, 1, 2, 3}:
            raise RuntimeError("Test set does not contain four directions")
        if not all(np.sum(y[train] == label) == 4 for label in range(4)):
            raise RuntimeError("Four-direction training classes are unbalanced")
        if not all(np.sum(y[test] == label) == 1 for label in range(4)):
            raise RuntimeError("Four-direction test classes are unbalanced")

        folds.append((train, test))

    if len(folds) != 5:
        raise RuntimeError(f"Expected five folds, found {len(folds)}")

    return (
        y,
        folds,
        0.25,
        "Song Step3_mvpa08 four labels and five leave-one-block-out chunks; "
        "25 percent chance confirmed from Arm A map values",
    )


def build_design(
    manifest: pd.DataFrame,
    model: str,
) -> tuple[np.ndarray, list[tuple[np.ndarray, np.ndarray]], float, str]:
    if model in NONCV_CONTEXT_MODELS:
        return build_noncv_context_design(manifest, model)
    if model in FOUR_DIRECTION_MODELS:
        return build_four_direction_design(manifest, model)
    raise ValueError(f"Unknown model: {model}")


def main(subject: str, model: str, n_jobs: int) -> None:
    started = time.time()
    label = f"sub-{subject}"

    base = (
        ROOT
        / "derivatives"
        / "arm-c"
        / "mvpa-glm-1stlevel"
        / label
    )
    betas = base / "condition_betas.nii.gz"
    manifest_path = base / "beta_manifest.tsv"
    mask = (
        ROOT
        / "derivatives"
        / "common-searchlight-masks"
        / label
        / "arm-b_explicit_mask.nii"
    )

    for path in (betas, manifest_path, mask):
        if not path.is_file():
            raise FileNotFoundError(path)

    output = ROOT / "derivatives" / "arm-c" / "mvpa" / model / label
    if output.exists():
        raise FileExistsError(f"Refusing to write existing path: {output}")

    manifest = pd.read_csv(manifest_path, sep="\t")
    required_columns = {
        "context",
        "direction",
        "block",
        "regressor",
        "n_trials",
    }
    if len(manifest) != 60 or set(manifest.columns) != required_columns:
        raise RuntimeError(
            f"Unexpected beta manifest: rows={len(manifest)}, "
            f"columns={list(manifest.columns)}"
        )

    y, folds, chance, design_source = build_design(manifest, model)

    fold_train_sizes = sorted({len(train) for train, _ in folds})
    fold_test_sizes = sorted({len(test) for _, test in folds})
    if len(fold_train_sizes) != 1 or len(fold_test_sizes) != 1:
        raise RuntimeError(
            f"Fold sizes are not constant: train={fold_train_sizes}, "
            f"test={fold_test_sizes}"
        )
    n_test_predictions = sum(len(test) for _, test in folds)
    predicted_step = 100.0 / n_test_predictions

    estimator = make_pipeline(
        StandardScaler(),
        SVC(kernel="linear", C=1.0),
    )
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
    searchlight.fit(str(betas), y)

    reference = nib.load(mask)
    valid = np.asarray(reference.dataobj) > 0
    scores = np.asarray(searchlight.scores_, dtype=np.float32)
    if scores.shape != reference.shape:
        raise RuntimeError(
            f"Score shape {scores.shape} does not match mask {reference.shape}"
        )
    if not np.isfinite(scores[valid]).all():
        raise RuntimeError("Non-finite searchlight scores inside process mask")

    output.mkdir(parents=True, exist_ok=False)

    accuracy = nib.Nifti1Image(
        scores,
        reference.affine,
        reference.header,
    )
    accuracy.set_data_dtype(np.float32)
    nib.save(accuracy, output / "accuracy.nii.gz")

    minus_chance = np.zeros_like(scores, dtype=np.float32)
    minus_chance[valid] = (scores[valid] - chance) * 100.0
    result = nib.Nifti1Image(
        minus_chance,
        reference.affine,
        reference.header,
    )
    result.set_data_dtype(np.float32)
    nib.save(result, output / "accuracy_minus_chance.nii.gz")

    metadata = {
        "tool": "nilearn.SearchLight+sklearn.SVC",
        "subject": subject,
        "model": model,
        "n_samples_in_beta_series": len(manifest),
        "n_folds": len(folds),
        "fold_train_n": fold_train_sizes[0],
        "fold_test_n": fold_test_sizes[0],
        "n_test_predictions": n_test_predictions,
        "predicted_quantization_percentage_points": predicted_step,
        "chance": chance,
        "accuracy_minus_chance_unit": "percentage points",
        "radius_mm": 9.0,
        "scaling": "StandardScaler within training fold",
        "classifier": "SVC(kernel='linear', C=1.0)",
        "n_jobs": n_jobs,
        "mask_voxels": int(valid.sum()),
        "finite_in_mask": True,
        "accuracy_min": float(scores[valid].min()),
        "accuracy_max": float(scores[valid].max()),
        "accuracy_mean": float(scores[valid].mean()),
        "runtime_seconds": time.time() - started,
        "design_source": design_source,
        "cv_subdivision": False
            if model in NONCV_CONTEXT_MODELS
            else "leave-one-block-out",
    }
    (output / "metadata.json").write_text(
        json.dumps(metadata, indent=2)
    )
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--subject", required=True)
    parser.add_argument("--model", choices=ALL_MODELS, required=True)
    parser.add_argument("--n-jobs", type=int, default=12)
    arguments = parser.parse_args()
    main(
        str(arguments.subject).zfill(2),
        arguments.model,
        arguments.n_jobs,
    )
