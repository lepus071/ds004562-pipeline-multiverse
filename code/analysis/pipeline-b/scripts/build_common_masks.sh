#!/usr/bin/env bash
set -euo pipefail

root="<DATA_ROOT>"
export FSLOUTPUTTYPE=NIFTI
mask_root="$root/derivatives/common-searchlight-masks"
log_root="$root/logs"
subjects=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 17 18 19 20 21 22 23)
if [[ ${MASK_SUBJECTS:-all} != all ]]; then subjects=("$MASK_SUBJECTS"); fi

ants="<ANTS_ROOT>/bin/antsApplyTransforms"
fslmaths="<FSL_ROOT>/share/fsl/bin/fslmaths"
fslstats="<FSL_ROOT>/share/fsl/bin/fslstats"
canonical_gz="$root/.templateflow/tpl-MNI152NLin6Asym/tpl-MNI152NLin6Asym_res-02_desc-brain_mask.nii.gz"
canonical_ref="$mask_root/tpl-MNI152NLin6Asym_res-02_desc-brain_mask.nii"
to_mni6="$root/.templateflow/tpl-MNI152NLin6Asym/tpl-MNI152NLin6Asym_from-MNI152NLin2009cAsym_mode-image_xfm.h5"
to_mni2009="$root/.templateflow/tpl-MNI152NLin2009cAsym/tpl-MNI152NLin2009cAsym_from-MNI152NLin6Asym_mode-image_xfm.h5"
qc_table="$log_root/common_searchlight_mask_qc.tsv"

for file in "$canonical_gz" "$to_mni6" "$to_mni2009"; do
    [[ -s $file ]] || { printf 'Missing or empty TemplateFlow resource: %s\n' "$file" >&2; exit 1; }
done
mkdir -p "$mask_root" "$log_root"
if [[ ! -s $canonical_ref ]]; then gunzip -c "$canonical_gz" > "$canonical_ref"; fi
if [[ ! -f $qc_table ]]; then
    printf 'subject\tcanonical_voxels\tarm_a_native_voxels\tarm_b_native_voxels\tarm_a_roundtrip_loss\tarm_b_roundtrip_loss\tpassed\n' > "$qc_table"
fi

for subject in "${subjects[@]}"; do
    label="sub-$subject"
    outdir="$mask_root/$label"
    mkdir -p "$outdir"
    printf '[%s] projecting GLM coverage to canonical space\n' "$label"
    MASK_SUBJECT="$subject" MASK_MODE=to_canonical matlab -batch \
        "run('<DATA_ROOT>/scripts/arm_b/Arm_common_mask_spm.m')"
    "$ants" -d 3 -i "$outdir/arm-a_canonical_spm15_coverage.nii" -r "$canonical_ref" \
        -o "$outdir/arm-a_canonical_coverage.nii" -n NearestNeighbor

    bmask="$root/derivatives/arm-b/glm-1stlevel/$label/mask.nii"
    bforward="$root/derivatives/fmriprep-ds004562/$label/ses-02fmri/anat/${label}_ses-02fmri_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5"
    binverse="$root/derivatives/fmriprep-ds004562/$label/ses-02fmri/anat/${label}_ses-02fmri_from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5"
    "$ants" -d 3 -i "$bmask" -r "$canonical_ref" \
        -o "$outdir/arm-b_canonical_coverage.nii" -n NearestNeighbor \
        -t "$to_mni6" -t "$bforward"

    "$fslmaths" "$outdir/arm-a_canonical_coverage.nii" -bin \
        -mul "$outdir/arm-b_canonical_coverage.nii" -mas "$canonical_ref" -bin \
        "$outdir/canonical_common_mask.nii"

    printf '[%s] pulling paired support to both native grids\n' "$label"
    MASK_SUBJECT="$subject" MASK_MODE=to_native matlab -batch \
        "run('<DATA_ROOT>/scripts/arm_b/Arm_common_mask_spm.m')"
    "$ants" -d 3 -i "$outdir/canonical_common_mask.nii" -r "$bmask" \
        -o "$outdir/arm-b_explicit_mask_unclipped.nii" -n NearestNeighbor \
        -t "$binverse" -t "$to_mni2009"

    amask="$root/ds004562/derivatives/spm-mvpa/glm-1stlevel/$label/mask.nii"
    "$fslmaths" "$outdir/arm-a_explicit_mask_unclipped.nii" -nan -bin -mas "$amask" -bin \
        "$outdir/arm-a_explicit_mask.nii"
    "$fslmaths" "$outdir/arm-b_explicit_mask_unclipped.nii" -nan -bin -mas "$bmask" -bin \
        "$outdir/arm-b_explicit_mask.nii"

    canonical_voxels=$("$fslstats" "$outdir/canonical_common_mask.nii" -l 0.5 -V | awk '{print $1}')
    arm_a_voxels=$("$fslstats" "$outdir/arm-a_explicit_mask.nii" -l 0.5 -V | awk '{print $1}')
    arm_b_voxels=$("$fslstats" "$outdir/arm-b_explicit_mask.nii" -l 0.5 -V | awk '{print $1}')
    arm_a_unclipped=$("$fslstats" "$outdir/arm-a_explicit_mask_unclipped.nii" -l 0.5 -V | awk '{print $1}')
    arm_b_unclipped=$("$fslstats" "$outdir/arm-b_explicit_mask_unclipped.nii" -l 0.5 -V | awk '{print $1}')
    arm_a_loss=$((arm_a_unclipped-arm_a_voxels))
    arm_b_loss=$((arm_b_unclipped-arm_b_voxels))
    passed=false
    if ((canonical_voxels > 0 && arm_a_voxels > 0 && arm_b_voxels > 0)); then passed=true; fi
    sed -i "/^${label}[[:space:]]/d" "$qc_table"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$canonical_voxels" \
        "$arm_a_voxels" "$arm_b_voxels" "$arm_a_loss" "$arm_b_loss" "$passed" >> "$qc_table"
    if [[ $passed == true ]]; then
        printf '{"subject":"%s","passed":true,"canonical_voxels":%s,"arm_a_native_voxels":%s,"arm_b_native_voxels":%s}\n' \
            "$label" "$canonical_voxels" "$arm_a_voxels" "$arm_b_voxels" > "$outdir/qc_passed.json"
    else
        printf '[%s] empty output mask; stopping\n' "$label" >&2
        exit 1
    fi
    printf '[%s] passed numeric QC\n' "$label"
done
