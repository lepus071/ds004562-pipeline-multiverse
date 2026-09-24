#!/usr/bin/env bash
set -euo pipefail

root="<DATA_ROOT>"
log_root="$root/logs/contract_decoding_cohort"
mkdir -p "$log_root"
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

status="$log_root/status.tsv"
[[ -f $status ]] || printf 'arm\tscript\texit_code\tfinished_at\n' > "$status"
for arm in arm-a arm-b; do
    suite="$root/contract_runs/cohort-$arm"
    for script in "${scripts[@]}"; do
        printf '%s %s starting\n' "$arm" "$script"
        set +e
        (cd "$suite/Code_fMRI_analysis" && CONTRACT_ARM="$arm" matlab -batch \
            "run('$suite/Code_fMRI_analysis/$script')") \
            > "$log_root/${arm}_${script%.m}.log" 2>&1
        code=$?
        set -e
        printf '%s\t%s\t%d\t%s\n' "$arm" "$script" "$code" "$(date --iso-8601=seconds)" >> "$status"
        if ((code != 0)); then
            printf '%s %s failed (%d); stopping\n' "$arm" "$script" "$code" >&2
            exit "$code"
        fi
        printf '%s %s complete\n' "$arm" "$script"
    done
done
printf 'Contract decoding cohort complete for both arms.\n'
