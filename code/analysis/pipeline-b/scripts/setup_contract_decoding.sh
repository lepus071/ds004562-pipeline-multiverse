#!/usr/bin/env bash
set -euo pipefail

root="<DATA_ROOT>"
mode=${1:-pilot}
[[ $mode == pilot || $mode == cohort ]] || { echo "Usage: $0 pilot|cohort" >&2; exit 2; }
subjects=(01)
if [[ $mode == cohort ]]; then
    subjects=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 17 18 19 20 21 22 23)
fi

scripts=(
  Step3_mvpa02_VisualLevel01_AllTask_MVPA.m
  Step3_mvpa03_MoveDirection01_Alltasks_MVPA.m
  Step3_mvpa04_TaskContext_CV01_90s_MVPA.m
  Step3_mvpa05_TaskContext_CV01_rotVSmirror_MVPA.m
  Step3_mvpa06_PreparePeriod01_90s_MVPA.m
  Step3_mvpa06_PreparePeriod04_rotVSmirror_MVPA.m
  Step3_mvpa07_Commonality01_90s_MVPA_context.m
  Step3_mvpa07_Commonality04_rotVSmirror01_MVPA_context.m
  Step3_mvpa08_FourDirection1_MVPA.m
)

for arm in arm-a arm-b; do
    suite="$root/contract_runs/${mode}-${arm}"
    bids="$suite/bids"
    code="$suite/Code_fMRI_analysis"
    mkdir -p "$code" "$suite/temp" "$bids/derivatives/spm-preproc" \
        "$bids/derivatives/spm-mvpa/glm-1stlevel"
    ln -sfn "$root/ds004562/derivatives/behavior" "$bids/derivatives/behavior"
    for subject in "${subjects[@]}"; do
        label="sub-$subject"
        ln -sfn "$root/ds004562/derivatives/spm-preproc/$label" \
            "$bids/derivatives/spm-preproc/$label"
        if [[ $arm == arm-a ]]; then
            glm="$root/ds004562/derivatives/spm-mvpa/glm-1stlevel/$label"
        else
            glm="$root/derivatives/arm-b/glm-1stlevel/$label"
        fi
        ln -sfn "$glm" "$bids/derivatives/spm-mvpa/glm-1stlevel/$label"
    done

    for script in "${scripts[@]}"; do
        cp "$root/song2023_code/Code_fMRI_analysis/$script" "$code/$script"
        # The sole analysis change: require the paired native explicit mask.
        sed -i "/beta_loc = /a\\    contractArm = getenv('CONTRACT_ARM');\n    assert(any(strcmp(contractArm, {'arm-a','arm-b'})), 'CONTRACT_ARM missing or invalid.');\n    cfg.files.mask = fullfile('<DATA_ROOT>/derivatives/common-searchlight-masks', results1st_subj(nsub).name, [contractArm '_explicit_mask.nii']);\n    assert(isfile(cfg.files.mask), 'Explicit mask missing: %s', cfg.files.mask);" "$code/$script"
        # The original sub-16 safeguard must follow identity, not loop position.
        sed -i "s/nsub == 16/strcmp(results1st_subj(nsub).name, 'sub-16')/g; s/nsub==16/strcmp(results1st_subj(nsub).name, 'sub-16')/g" "$code/$script"
    done

    matlab -batch "pathBIDS='$bids'; pathSPM='<SPM12_ROOT>'; save('$suite/temp/tempFileForAnalysis.mat','pathBIDS','pathSPM');"
    {
        printf 'mode=%s\narm=%s\nsubjects=' "$mode" "$arm"
        printf '%s ' "${subjects[@]}"
        printf '\nsource_commit=81be0e3\nmask_contract=<DATA_ROOT>/docs/common_searchlight_mask_contract.md\n'
    } > "$suite/PROVENANCE.txt"
done

printf 'Prepared isolated %s contract-decoding suites for %d subject(s).\n' "$mode" "${#subjects[@]}"
