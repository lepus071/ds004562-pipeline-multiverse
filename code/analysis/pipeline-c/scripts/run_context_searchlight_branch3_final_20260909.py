#!/usr/bin/env python3
"""Review-only Arm C proposal for Song branches 3 and 4; do not run before approval."""
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

ROOT = Path("<DATA_ROOT>")
BRANCHES = {
    "MVPA_TaskContext_CV_posneg90s": [
        (("rotation-90", "upward"), ("rotation+90", "upward"),
         ("rotation-90", "rightward"), ("rotation+90", "leftward")),
        (("rotation-90", "leftward"), ("rotation+90", "leftward"),
         ("rotation-90", "upward"), ("rotation+90", "downward")),
        (("rotation-90", "rightward"), ("rotation+90", "rightward"),
         ("rotation-90", "downward"), ("rotation+90", "upward")),
        (("rotation-90", "downward"), ("rotation+90", "downward"),
         ("rotation-90", "leftward"), ("rotation+90", "rightward")),
        (("rotation-90", "rightward"), ("rotation+90", "leftward"),
         ("rotation-90", "upward"), ("rotation+90", "upward")),
        (("rotation-90", "upward"), ("rotation+90", "downward"),
         ("rotation-90", "leftward"), ("rotation+90", "leftward")),
        (("rotation-90", "downward"), ("rotation+90", "upward"),
         ("rotation-90", "rightward"), ("rotation+90", "rightward")),
        (("rotation-90", "leftward"), ("rotation+90", "rightward"),
         ("rotation-90", "downward"), ("rotation+90", "downward")),
    ],
    "MVPA_TaskContext_CV_rotationVSmirror": [
        (("rotation-90", "upward"), ("mirror", "upward"),
         ("rotation-90", "rightward"), ("mirror", "downward")),
        (("rotation+90", "upward"), ("mirror", "upward"),
         ("rotation+90", "leftward"), ("mirror", "downward")),
        (("rotation-90", "leftward"), ("mirror", "leftward"),
         ("rotation-90", "downward"), ("mirror", "rightward")),
        (("rotation+90", "leftward"), ("mirror", "leftward"),
         ("rotation+90", "upward"), ("mirror", "rightward")),
        (("rotation-90", "leftward"), ("mirror", "upward"),
         ("rotation-90", "downward"), ("mirror", "downward")),
        (("rotation+90", "rightward"), ("mirror", "upward"),
         ("rotation+90", "downward"), ("mirror", "downward")),
        (("rotation-90", "upward"), ("mirror", "leftward"),
         ("rotation-90", "rightward"), ("mirror", "rightward")),
        (("rotation+90", "downward"), ("mirror", "leftward"),
         ("rotation+90", "rightward"), ("mirror", "rightward")),
        (("rotation-90", "rightward"), ("mirror", "downward"),
         ("rotation-90", "upward"), ("mirror", "upward")),
        (("rotation+90", "leftward"), ("mirror", "downward"),
         ("rotation+90", "upward"), ("mirror", "upward")),
        (("rotation-90", "downward"), ("mirror", "rightward"),
         ("rotation-90", "leftward"), ("mirror", "leftward")),
        (("rotation+90", "upward"), ("mirror", "rightward"),
         ("rotation+90", "leftward"), ("mirror", "leftward")),
        (("rotation-90", "downward"), ("mirror", "downward"),
         ("rotation-90", "leftward"), ("mirror", "upward")),
        (("rotation+90", "downward"), ("mirror", "downward"),
         ("rotation+90", "rightward"), ("mirror", "upward")),
        (("rotation-90", "rightward"), ("mirror", "rightward"),
         ("rotation-90", "upward"), ("mirror", "leftward")),
        (("rotation+90", "rightward"), ("mirror", "rightward"),
         ("rotation+90", "downward"), ("mirror", "leftward")),
    ],
}


def condition_indices(manifest: pd.DataFrame, context: str, direction: str) -> np.ndarray:
    indices = manifest.index[
        manifest["context"].eq(context) & manifest["direction"].eq(direction)
    ].to_numpy(dtype=int)
    if len(indices) != 5:
        raise RuntimeError(f"Expected 5 estimates for {context}/{direction}, found {len(indices)}")
    return indices


def build_design(manifest: pd.DataFrame, branch: str) -> tuple[np.ndarray, list[tuple[np.ndarray, np.ndarray]]]:
    context_label = {"rotation+90": 0, "rotation-90": 1, "mirror": 2}
    y = manifest["context"].map(context_label).to_numpy(dtype=int)
    if np.any(pd.isna(manifest["context"].map(context_label))):
        raise RuntimeError("Unknown context in beta manifest")

    folds: list[tuple[np.ndarray, np.ndarray]] = []
    for train_first, train_second, test_first, test_second in BRANCHES[branch]:
        train_base = np.concatenate(
            [condition_indices(manifest, *train_first), condition_indices(manifest, *train_second)]
        )
        test_base = np.concatenate(
            [condition_indices(manifest, *test_first), condition_indices(manifest, *test_second)]
        )
        for repetition in range(5):
            test = np.asarray([test_base[repetition], test_base[5 + repetition]])
            held_out = {int(train_base[repetition]), int(train_base[5 + repetition])}
            train = np.asarray([index for index in train_base if int(index) not in held_out])
            if len(train) != 8 or len(test) != 2:
                raise RuntimeError("Unexpected train/test sample count")
            if set(train) & set(test):
                raise RuntimeError("Train/test samples overlap")
            if set(y[train]) != set(y[test]) or len(set(y[train])) != 2:
                raise RuntimeError("Fold is not binary cross-context classification")
            train_directions = set(manifest.iloc[train]["direction"])
            test_directions = set(manifest.iloc[test]["direction"])
            if train_directions & test_directions:
                raise RuntimeError("Training and test directions overlap")
            folds.append((train, test.copy()))

    expected = 40 if branch == "MVPA_TaskContext_CV_posneg90s" else 80
    if len(folds) != expected:
        raise RuntimeError(f"Expected {expected} folds, constructed {len(folds)}")
    return y, folds


def main(subject: str, branch: str, n_jobs: int) -> None:
    started = time.time()
    label = f"sub-{subject}"
    base = ROOT / "derivatives" / "arm-c" / "mvpa-glm-1stlevel" / label
    betas = base / "condition_betas.nii.gz"
    manifest_path = base / "beta_manifest.tsv"
    mask = ROOT / "derivatives" / "common-searchlight-masks" / label / "arm-b_explicit_mask.nii"
    for path in (betas, manifest_path, mask):
        if not path.is_file():
            raise FileNotFoundError(path)

    output_branch = branch
    output = ROOT / "derivatives" / "arm-c" / "mvpa" / output_branch / label
    if output.exists():
        raise FileExistsError(f"Refusing to write existing path: {output}")

    manifest = pd.read_csv(manifest_path, sep="\t")
    if len(manifest) != 60:
        raise RuntimeError(f"Expected 60 beta estimates, found {len(manifest)}")
    y, folds = build_design(manifest, branch)

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
    searchlight.fit(str(betas), y)

    reference = nib.load(mask)
    scores = np.asarray(searchlight.scores_, dtype=np.float32)
    valid = np.asarray(reference.dataobj) > 0
    if scores.shape != reference.shape or not np.isfinite(scores[valid]).all():
        raise RuntimeError("Invalid searchlight scores")

    output.mkdir(parents=True, exist_ok=False)
    accuracy = nib.Nifti1Image(scores, reference.affine, reference.header)
    accuracy.set_data_dtype(np.float32)
    nib.save(accuracy, output / "accuracy.nii.gz")

    minus_chance = np.zeros_like(scores, dtype=np.float32)
    minus_chance[valid] = (scores[valid] - 0.5) * 100.0
    result = nib.Nifti1Image(minus_chance, reference.affine, reference.header)
    result.set_data_dtype(np.float32)
    nib.save(result, output / "accuracy_minus_chance.nii.gz")

    metadata = {
        "tool": "nilearn.SearchLight+sklearn.SVC",
        "subject": subject,
        "branch": branch,
        "output_branch": output_branch,
        "test_selection": "one repetition from each of two test conditions per fold",
        "n_samples": 60,
        "n_folds": len(folds),
        "fold_train_n": 8,
        "fold_test_n": 2,
        "n_test_predictions": 80,
        "accuracy_quantization_percentage_points": 1.25,
        "chance": 0.5,
        "accuracy_minus_chance_unit": "percentage points",
        "radius_mm": 9.0,
        "arm_c_radius_note": "9.0 mm spherical SearchLight radius, retained from Arm C branches 1 and 2",
        "song_radius_note": "3 voxels on the 3 x 3 x 3.6 mm Song grid; not the same neighbourhood as Arm C's 9.0 mm radius",
        "scaling": "StandardScaler within training fold",
        "classifier": "SVC(kernel='linear', C=1.0)",
        "n_jobs": n_jobs,
        "mask_voxels": int(valid.sum()),
        "finite_in_mask": True,
        "accuracy_min": float(scores[valid].min()),
        "accuracy_max": float(scores[valid].max()),
        "accuracy_mean": float(scores[valid].mean()),
        "runtime_seconds": time.time() - started,
        "design_source": "Song mvpa04/mvpa05: repeated test matrix starts at zero and selects one repetition from each test condition",
        "temporal_adjacency_enforced": False,
    }
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2))
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--subject", required=True)
    parser.add_argument("--branch", choices=list(BRANCHES), required=True)
    parser.add_argument("--n-jobs", type=int, default=12)
    arguments = parser.parse_args()
    main(str(arguments.subject).zfill(2), arguments.branch, arguments.n_jobs)
