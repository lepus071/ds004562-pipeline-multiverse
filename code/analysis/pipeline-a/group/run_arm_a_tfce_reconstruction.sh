#!/usr/bin/env bash
set -euo pipefail

project_root="<DATA_ROOT>"
mvpa_root="$project_root/ds004562/derivatives/spm-mvpa"
tfce_root="$mvpa_root/TFCE_reconstruction"
script_root="$project_root/scripts/arm_a"
permutations=5000
seed=20260903
max_parallel=${TFCE_MAX_PARALLEL:-2}

export FSLDIR=${FSLDIR:-<FSL_ROOT>}
source "$FSLDIR/etc/fslconf/fsl.sh"
export FSLOUTPUTTYPE=NIFTI_GZ

matlab -batch "addpath('$script_root'); prepare_arm_a_tfce_reconstruction"

fsl_version=$(tr -d '\n' < "$FSLDIR/etc/fslversion")
randomise_help_version=$(randomise --help 2>&1 | sed -n 's/^randomise v//p' | head -n 1 || true)
printf 'FSL=%s randomise=%s\n' "$fsl_version" "$randomise_help_version" > "$tfce_root/software_versions.txt"

run_one() {
    local label=$1
    local source_mask=$2
    local analysis_dir="$tfce_root/$label"
    local output_root="$analysis_dir/randomise"

    if [[ -s "${output_root}_tfce_corrp_tstat1.nii.gz" ]] &&
       grep -q 'Finished, exiting.' "$analysis_dir/randomise.log"; then
        printf 'Skipping completed analysis: %s\n' "$label"
        return 0
    fi

    mapfile -t scans < "$analysis_dir/scans.txt"
    if [[ ${#scans[@]} -ne 22 ]]; then
        printf 'Expected 22 scans for %s, found %d\n' "$label" "${#scans[@]}" >&2
        return 1
    fi

    fslmerge -t "$analysis_dir/input_4d.nii.gz" "${scans[@]}"
    fslmaths "$source_mask" -bin "$analysis_dir/mask.nii.gz"

    local volumes
    volumes=$(fslval "$analysis_dir/input_4d.nii.gz" dim4)
    if [[ $volumes -ne 22 ]]; then
        printf 'Merged input for %s has dim4=%s, expected 22\n' "$label" "$volumes" >&2
        return 1
    fi

    randomise \
        -i "$analysis_dir/input_4d.nii.gz" \
        -o "$output_root" \
        -d "$analysis_dir/design.mat" \
        -t "$analysis_dir/design.con" \
        -m "$analysis_dir/mask.nii.gz" \
        -n "$permutations" \
        -T --tfce_H=2 --tfce_E=0.5 --tfce_C=6 \
        --uncorrp -R -P -N --seed="$seed" \
        > "$analysis_dir/randomise.log" 2>&1

    fslmaths "${output_root}_tfce_corrp_tstat1.nii.gz" -thr 0.95 -bin \
        "$analysis_dir/significant_fwe05.nii.gz"
    fslstats "$analysis_dir/significant_fwe05.nii.gz" -V \
        > "$analysis_dir/significant_fwe05_voxels.txt"
}
export -f run_one
export project_root mvpa_root tfce_root permutations seed FSLDIR FSLOUTPUTTYPE

while IFS=$'\t' read -r label source_mask source_group_model; do
    while (( $(jobs -pr | wc -l) >= max_parallel )); do
        wait -n
    done
    run_one "$label" "$source_mask" &
done < <(tail -n +2 "$tfce_root/analyses.tsv")
wait

# Figure 9 reports both FWE and FDR control. randomise stores permutation p maps as 1-p.
figure9_dir="$tfce_root/figure9_prepare_rotation_vs_mirror"
fdr \
    -i "$figure9_dir/randomise_tfce_p_tstat1.nii.gz" \
    -m "$figure9_dir/mask.nii.gz" \
    --oneminusp --positivecorr -q 0.05 \
    -a "$figure9_dir/randomise_tfce_fdrp_tstat1.nii.gz" \
    > "$figure9_dir/fdr_q05.txt"
fslmaths "$figure9_dir/randomise_tfce_fdrp_tstat1.nii.gz" -thr 0.95 -bin \
    "$figure9_dir/significant_fdr05.nii.gz"
fslstats "$figure9_dir/significant_fdr05.nii.gz" -V \
    > "$figure9_dir/significant_fdr05_voxels.txt"

matlab -batch "addpath('$script_root'); generate_arm_a_tfce_reconstruction_figures"

date --iso-8601=seconds > "$tfce_root/COMPLETED"
printf 'Arm A TFCE reconstruction completed: %s\n' "$tfce_root"
