#!/usr/bin/env bash
set -euo pipefail
root="<DATA_ROOT>"
export FSLOUTPUTTYPE=NIFTI
out="$root/derivatives/contract-normalized/group-masks"
ref="$root/derivatives/contract-normalized/reference_spm_grid.nii"
ants="<ANTS_ROOT>/bin/antsApplyTransforms"
fslmaths="<FSL_ROOT>/share/fsl/bin/fslmaths"
mkdir -p "$out/subjects"
full=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 17 18 19 20 21 22 23)
strict=(01 02 03 04 05 06 07 08 09 11 13 15 17 19 20 21 22 23)

for subject in "${full[@]}"; do
    input="$root/derivatives/common-searchlight-masks/sub-$subject/canonical_common_mask.nii"
    output="$out/subjects/sub-${subject}_space-SPM2mm_common_mask.nii"
    "$ants" -d 3 -i "$input" -r "$ref" -o "$output" -n NearestNeighbor
    "$fslmaths" "$output" -bin "$output"
done

build_intersection() {
    local name=$1; shift
    local subjects=("$@") target="$out/${name}_common_mask.nii"
    cp "$out/subjects/sub-${subjects[0]}_space-SPM2mm_common_mask.nii" "$target"
    for subject in "${subjects[@]:1}"; do
        "$fslmaths" "$target" -mas "$out/subjects/sub-${subject}_space-SPM2mm_common_mask.nii" -bin "$target"
    done
}
build_intersection D1-full "${full[@]}"
build_intersection D1-strict "${strict[@]}"
printf 'D1-full '; fslstats "$out/D1-full_common_mask.nii" -V
printf 'D1-strict '; fslstats "$out/D1-strict_common_mask.nii" -V
