#!/usr/bin/env bash
set -euo pipefail

python_bin=python
decoder="<DATA_ROOT>/scripts/arm_c/run_context_searchlight_branch3_final_20260909.py"
output_root="<DATA_ROOT>/derivatives/arm-c/mvpa/MVPA_TaskContext_CV_posneg90s"
subjects=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 17 18 19 20 21 22 23)

if [[ -e "$output_root" ]]; then
    printf 'Refusing to write existing branch root: %s\n' "$output_root" >&2
    exit 1
fi

for subject in "${subjects[@]}"; do
    printf 'SUBJECT_START sub-%s %s\n' "$subject" "$(date --iso-8601=seconds)"
    env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
        "$python_bin" "$decoder" \
        --subject "$subject" \
        --branch MVPA_TaskContext_CV_posneg90s \
        --n-jobs 12
    printf 'SUBJECT_END sub-%s %s\n' "$subject" "$(date --iso-8601=seconds)"
done

printf 'COHORT_COMPLETE %s\n' "$(date --iso-8601=seconds)"
