# Common explicit searchlight-mask contract — Arms A and B

**Frozen: 2026-09-03, before Arm B decoding.**

## Objective

For each frozen subject, both arms must decode the same anatomically defined and mutually
estimable support. Existing GLM `mask.nii` files are inputs to coverage estimation only; neither
arm may use its own implicit mask directly as the TDT searchlight mask.

## Canonical space

- Space: TemplateFlow `MNI152NLin6Asym` (the closest explicit template definition for the SPM
  MNI coordinate system).
- Reference: `tpl-MNI152NLin6Asym_res-02_desc-brain_mask.nii.gz`.
- Interpolation for masks: nearest neighbour only.
- Values are binarized after every resampling operation (`> 0.5`).

## Per-subject construction

For each subject in `subject_manifest.json:D1_full`:

1. Map Arm A's first-level `mask.nii` to the canonical grid with its SPM forward deformation
   `y_sub-*_T1w.nii`.
2. Map Arm B's first-level `mask.nii` from T1w to `MNI152NLin2009cAsym` with the subject's
   fMRIPrep transform, then to `MNI152NLin6Asym` with TemplateFlow's template-to-template
   transform.
3. Intersect the two canonical binary masks with the canonical brain mask. This is the paired
   common estimable support for that subject.
4. Pull that one intersection back into Arm A's native EPI grid and Arm B's T1w analysis grid
   using the inverse of the transformations above.
5. Intersect each pulled mask once more with that arm's GLM mask. Record any voxel loss caused
   by round-trip resampling.

## Decoding rule

- Set `cfg.files.mask` explicitly to the resulting arm/subject mask in every TDT script.
- Keep `cfg.searchlight.radius = 3` voxels as published; the documented grid-orientation
  difference remains an unavoidable between-arm preprocessing difference.
- Existing Arm A decoding outputs are non-compliant because they used automatic GLM masks.
  Preserve them as historical outputs, but rerun both arms into new contract-labelled output
  directories. Never mix old and new maps.
- Build D1-full subject maps first. D1-strict is a group-level subset of the same subject maps;
  it does not require separate first-level decoding.

## QC gate before decoding

For all 22 paired masks, require:

- non-empty masks in both native grids;
- every selected native voxel lies inside its arm's GLM mask;
- canonical paired-mask voxel counts and native round-trip counts are recorded;
- montage inspection for at least sub-01 plus the four high-motion subjects 10, 12, 14, 18;
- no left-right flip, gross truncation, or transform failure.

Only after this gate passes may contract-labelled Arm A and Arm B searchlight decoding start.
