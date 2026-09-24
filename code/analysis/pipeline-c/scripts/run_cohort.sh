#!/usr/bin/env bash
set -euo pipefail

root="<DATA_ROOT>"
python_bin=python
mode=${1:-all}
glm_jobs=${ARM_C_GLM_JOBS:-20}
searchlight_jobs=${ARM_C_SEARCHLIGHT_JOBS:-24}
subjects=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 17 18 19 20 21 22 23)
branches=(MVPA_VisualDirection_Alltask MVPA_MoveDirection_Alltasks)

run_glm() {
  for subject in "${subjects[@]}"; do
    glm_command=("$python_bin" "$root/scripts/arm_c/build_mvpa_glm.py" --subject "$subject" --n-jobs "$glm_jobs")
    env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 "${glm_command[@]}"
  done
}

run_mvpa() {
  for subject in "${subjects[@]}"; do
    for branch in "${branches[@]}"; do
      mvpa_command=("$python_bin" "$root/scripts/arm_c/run_searchlight.py" --subject "$subject" --branch "$branch" --n-jobs "$searchlight_jobs")
      env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 "${mvpa_command[@]}"
    done
  done
}

case "$mode" in
  glm)
    run_glm
    ;;
  mvpa)
    run_mvpa
    ;;
  normalize)
    "$python_bin" "$root/scripts/arm_c/normalize_arm_c.py"
    ;;
  group)
    "$python_bin" "$root/scripts/arm_c/compute_core_consistency.py"
    ;;
  all)
    run_glm
    run_mvpa
    "$python_bin" "$root/scripts/arm_c/normalize_arm_c.py"
    "$python_bin" "$root/scripts/arm_c/compute_core_consistency.py"
    ;;
  *)
    printf 'Usage: %s {glm|mvpa|normalize|group|all}\n' "$0" >&2
    exit 2
    ;;
esac
