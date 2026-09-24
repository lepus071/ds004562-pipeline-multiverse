#!/usr/bin/env bash
set -euo pipefail

project_root="<DATA_ROOT>"
log_dir="$project_root/logs"
mkdir -p "$log_dir"
log_file="$log_dir/arm_b_stage_inputs_$(date +%Y%m%d_%H%M%S).log"

cd "$project_root"
exec matlab -batch "run('$project_root/scripts/arm_b/ArmB_stage_inputs.m')" 2>&1 | tee "$log_file"
