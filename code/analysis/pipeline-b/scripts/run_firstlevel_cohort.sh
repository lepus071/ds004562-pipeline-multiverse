#!/usr/bin/env bash
set -euo pipefail

project_root="<DATA_ROOT>"
log_dir="$project_root/logs/arm_b_firstlevel"
mkdir -p "$log_dir"

# Frozen D1-full order; sub-01 is the separately validated pilot.
subjects=(02 03 04 05 06 07 08 09 10 11 12 13 14 15 17 18 19 20 21 22 23)

status_file="$log_dir/status.tsv"
if [[ ! -f "$status_file" ]]; then
    printf 'subject\texit_code\tfinished_at\n' > "$status_file"
fi

for subject in "${subjects[@]}"; do
    output="$project_root/derivatives/arm-b/glm-1stlevel/sub-$subject/SPM.mat"
    if [[ -f "$output" ]]; then
        printf 'sub-%s already complete; skipping\n' "$subject"
        continue
    fi
    printf 'sub-%s starting\n' "$subject"
    set +e
    ARM_B_SUBJECT="$subject" matlab -batch \
        "run('<DATA_ROOT>/scripts/arm_b/ArmB_firstlevel_glm.m')" \
        > "$log_dir/sub-$subject.log" 2>&1
    exit_code=$?
    set -e
    printf 'sub-%s\t%d\t%s\n' "$subject" "$exit_code" "$(date --iso-8601=seconds)" >> "$status_file"
    if (( exit_code != 0 )); then
        printf 'sub-%s failed with exit code %d; stopping cohort\n' "$subject" "$exit_code" >&2
        exit "$exit_code"
    fi
    printf 'sub-%s complete\n' "$subject"
done

printf 'Arm B first-level cohort complete\n'
