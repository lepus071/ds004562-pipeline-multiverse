#!/usr/bin/env python3
"""Compute Arm A/B/C group summaries and common-core consistency metrics."""
from __future__ import annotations
import argparse
import json
from pathlib import Path

import nibabel as nib
import numpy as np
import pandas as pd
from scipy.stats import spearmanr, t

ROOT = Path("<DATA_ROOT>")
NORM_ROOT = ROOT / "derivatives" / "contract-normalized"
BRANCHES = [
    "MVPA_VisualDirection_Alltask",
    "MVPA_MoveDirection_Alltasks",
    "MVPA_TaskContext_CV_posneg90s",
    "MVPA_TaskContext_CV_rotationVSmirror",
]
ARMS = ["a", "b", "c"]
PAIRS = [("a", "b"), ("a", "c"), ("b", "c")]


def load_stack(arm: str, branch: str, subjects: list[str], reference: nib.spatialimages.SpatialImage) -> np.ndarray:
    maps = []
    for sub in subjects:
        path = NORM_ROOT / f"arm-{arm}" / branch / f"sub-{sub}" / "s8wres_accuracy_minus_chance.nii"
        if not path.is_file():
            raise FileNotFoundError(path)
        image = nib.load(path)
        data = np.asarray(image.dataobj, dtype=np.float32)
        if image.shape != reference.shape or np.max(np.abs(image.affine - reference.affine)) >= 1e-5:
            raise RuntimeError(f"grid mismatch: {path}")
        if not np.isfinite(data).all():
            raise RuntimeError(f"non-finite data: {path}")
        maps.append(data)
    return np.stack(maps, axis=-1)


def t_map(stack: np.ndarray) -> np.ndarray:
    n = stack.shape[-1]
    denominator = np.std(stack, axis=-1, ddof=1) / np.sqrt(n)
    result = np.divide(np.mean(stack, axis=-1), denominator, out=np.zeros(stack.shape[:-1], dtype=np.float32), where=denominator > 0)
    result[~np.isfinite(result)] = 0
    return result


def write_map(reference: nib.spatialimages.SpatialImage, path: Path, data: np.ndarray, mask: np.ndarray) -> None:
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite existing output: {path}")
    output = np.asarray(data, dtype=np.float32).copy()
    output[~mask] = 0
    image = nib.Nifti1Image(output, reference.affine, reference.header)
    image.set_data_dtype(np.float32)
    nib.save(image, path)


def grade(rho: float) -> str:
    if rho >= 0.7:
        return "high"
    if rho >= 0.4:
        return "partial"
    return "divergent"


def peak(mean_map: np.ndarray, mask: np.ndarray, affine: np.ndarray) -> tuple[float, np.ndarray]:
    valid_indices = np.flatnonzero(mask)
    flat_index = valid_indices[int(np.argmax(mean_map.flat[valid_indices]))]
    voxel = np.asarray(np.unravel_index(flat_index, mean_map.shape))
    xyz = nib.affines.apply_affine(affine, voxel)
    return float(mean_map.flat[flat_index]), xyz


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--branch",
        action="append",
        choices=BRANCHES,
        required=True,
        help="Branch to process; repeat for multiple branches",
    )
    parser.add_argument("--metrics-output", type=Path, required=True)
    parser.add_argument("--summary-output", type=Path, required=True)
    args = parser.parse_args()
    for output in (args.metrics_output, args.summary_output):
        if output.exists():
            raise FileExistsError(f"Refusing to overwrite existing output: {output}")

    manifest = json.loads((ROOT / "docs" / "subject_manifest.json").read_text())
    cohorts = {
        "D1-full": [str(s).zfill(2) for s in manifest["D1_full"]["subjects"]],
        "D1-strict": [str(s).zfill(2) for s in manifest["D1_strict"]["subjects"]],
    }
    reference = nib.load(NORM_ROOT / "reference_spm_grid.nii")
    rows = []
    for cohort, subjects in cohorts.items():
        mask_path = NORM_ROOT / "group-masks" / f"{cohort}_common_mask.nii"
        mask_image = nib.load(mask_path)
        mask = np.asarray(mask_image.dataobj) > 0.5
        if mask_image.shape != reference.shape or not np.any(mask):
            raise RuntimeError(f"invalid mask: {mask_path}")
        n = len(subjects)
        threshold = float(t.ppf(0.999, n - 1))
        for branch in args.branch:
            stacks = {arm: load_stack(arm, branch, subjects, reference) for arm in ARMS}
            means = {arm: np.mean(stack, axis=-1) for arm, stack in stacks.items()}
            tmaps = {arm: t_map(stack) for arm, stack in stacks.items()}
            output_dir = NORM_ROOT / "group-models" / cohort / branch
            output_dir.mkdir(parents=True, exist_ok=True)
            write_map(reference, output_dir / "arm-c_mean.nii", means["c"], mask)
            write_map(reference, output_dir / "arm-c_onesample_t.nii", tmaps["c"], mask)
            for first, second in [("a", "c"), ("b", "c")]:
                difference = stacks[second] - stacks[first]
                stem = f"arm-{second}_minus_arm-{first}"
                write_map(reference, output_dir / f"{stem}_mean.nii", np.mean(difference, axis=-1), mask)
                write_map(reference, output_dir / f"{stem}_paired_t.nii", t_map(difference), mask)

            for first, second in PAIRS:
                first_values = means[first][mask]
                second_values = means[second][mask]
                rho = float(spearmanr(first_values, second_values).statistic)
                significant_first = (tmaps[first] > threshold) & mask
                significant_second = (tmaps[second] > threshold) & mask
                denominator = int(significant_first.sum() + significant_second.sum())
                dice = float(2 * np.logical_and(significant_first, significant_second).sum() / denominator) if denominator else np.nan
                peak_first, xyz_first = peak(means[first], mask, reference.affine)
                peak_second, xyz_second = peak(means[second], mask, reference.affine)
                subject_rhos = [
                    float(spearmanr(stacks[first][..., index][mask], stacks[second][..., index][mask]).statistic)
                    for index in range(n)
                ]
                global_first = np.mean(stacks[first][mask, :], axis=0)
                global_second = np.mean(stacks[second][mask, :], axis=0)
                voxel_difference = second_values - first_values
                rows.append({
                    "cohort": cohort,
                    "n": n,
                    "branch": branch,
                    "pair": f"arm-{first}_vs_arm-{second}",
                    "mask_voxels": int(mask.sum()),
                    "spearman_rho": rho,
                    "grade": grade(rho),
                    "mean_subject_spearman": float(np.mean(subject_rhos)),
                    "median_subject_spearman": float(np.median(subject_rhos)),
                    "min_subject_spearman": float(np.min(subject_rhos)),
                    "max_subject_spearman": float(np.max(subject_rhos)),
                    "dice_p001_unc": dice,
                    "tcrit_p001_one_sided": threshold,
                    f"sigvox_arm_{first}": int(significant_first.sum()),
                    f"sigvox_arm_{second}": int(significant_second.sum()),
                    f"peak_arm_{first}": peak_first,
                    f"peak_arm_{second}": peak_second,
                    "peak_distance_mm": float(np.linalg.norm(xyz_first - xyz_second)),
                    f"global_mean_arm_{first}": float(np.mean(global_first)),
                    f"global_mean_arm_{second}": float(np.mean(global_second)),
                    "group_map_mean_difference_second_minus_first": float(np.mean(voxel_difference)),
                    "group_map_mae": float(np.mean(np.abs(voxel_difference))),
                    "group_map_rmse": float(np.sqrt(np.mean(voxel_difference ** 2))),
                })
                print(f"{cohort} {branch} arm-{first}/arm-{second}: rho={rho:.3f} ({grade(rho)}), mean subject rho={np.mean(subject_rhos):.3f}", flush=True)

    report = pd.DataFrame(rows)
    report.to_csv(args.metrics_output, sep="\t", index=False)
    summary = {
        "scope": "explicitly selected branches",
        "cohorts": {name: len(values) for name, values in cohorts.items()},
        "branches": args.branch,
        "pairs": [f"arm-{a}_vs_arm-{b}" for a, b in PAIRS],
        "primary_metric": "Spearman rho between unthresholded group-mean maps in frozen cohort mask",
        "grade_cutoffs": {"high": "rho >= .7", "partial": ".4 <= rho < .7", "divergent": "rho < .4"},
        "metrics_tsv": str(args.metrics_output),
    }
    args.summary_output.write_text(json.dumps(summary, indent=2))
    print(f"wrote {args.metrics_output} ({len(report)} rows)")


if __name__ == "__main__":
    main()
