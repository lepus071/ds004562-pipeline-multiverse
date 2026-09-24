#!/usr/bin/env bash
set -euo pipefail
root="<DATA_ROOT>/derivatives/arm-c/mvpa/MVPA_TaskContext_posneg90s"
script="<DATA_ROOT>/scripts/arm_c/run_remaining_searchlights_stage2_20260909.py"
subjects=(02 03 04 05 06 07 08 09 10 11 12 13 14 15 17 18 19 20 21 22 23)
test -f "$root/sub-01/metadata.json"
grep -q "\"n_folds\": 8" "$root/sub-01/metadata.json"
grep -q "\"fold_test_n\": 10" "$root/sub-01/metadata.json"
for subject in "${subjects[@]}"; do
    test ! -e "$root/sub-$subject"
done
echo "COHORT_REMAINDER_START $(date --iso-8601=seconds)"
for subject in "${subjects[@]}"; do
    echo "SUBJECT_START sub-$subject $(date --iso-8601=seconds)"
    python "$script" --subject "$subject" --model MVPA_TaskContext_posneg90s --n-jobs 12
    echo "SUBJECT_END sub-$subject $(date --iso-8601=seconds)"
done
echo "COHORT_COMPLETE $(date --iso-8601=seconds)"
