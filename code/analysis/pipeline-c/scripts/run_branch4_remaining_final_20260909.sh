#!/usr/bin/env bash
set -euo pipefail

root="<DATA_ROOT>/derivatives/arm-c/mvpa/MVPA_TaskContext_CV_rotationVSmirror"
pilot="$root/sub-01/metadata.json"
script="<DATA_ROOT>/scripts/arm_c/run_context_searchlight_branch4_final_20260909.py"
subjects=(02 03 04 05 06 07 08 09 10 11 12 13 14 15 17 18 19 20 21 22 23)

test -f "$pilot"
grep -q '"n_folds": 80' "$pilot"
grep -q '"n_test_predictions": 160' "$pilot"
grep -q '"accuracy_quantization_percentage_points": 0.625' "$pilot"
for subject in "${subjects[@]}"; do
    test ! -e "$root/sub-$subject"
done

echo "COHORT_REMAINDER_START $(date --iso-8601=seconds)"
for subject in "${subjects[@]}"; do
    echo "SUBJECT_START sub-$subject $(date --iso-8601=seconds)"
    python "$script" \
        --subject "$subject" \
        --branch MVPA_TaskContext_CV_rotationVSmirror \
        --n-jobs 12
    echo "SUBJECT_END sub-$subject $(date --iso-8601=seconds)"
done
echo "COHORT_COMPLETE $(date --iso-8601=seconds)"
