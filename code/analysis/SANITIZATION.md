# Sanitization report

Counts are replacements made while copying; zero-count files are omitted.

- `pipeline-a/InitializeForAnalysis.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa02_VisualLevel01_AllTask_MVPA.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa02_VisualLevel01_AllTask_MVPA.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa03_MoveDirection01_Alltasks_MVPA.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa03_MoveDirection01_Alltasks_MVPA.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa04_TaskContext_CV01_90s_MVPA.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa04_TaskContext_CV01_90s_MVPA.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa05_TaskContext_CV01_rotVSmirror_MVPA.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa05_TaskContext_CV01_rotVSmirror_MVPA.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa06_PreparePeriod01_90s_MVPA.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa06_PreparePeriod01_90s_MVPA.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa06_PreparePeriod04_rotVSmirror_MVPA.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa06_PreparePeriod04_rotVSmirror_MVPA.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa07_Commonality01_90s_MVPA_context.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa07_Commonality01_90s_MVPA_context.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa07_Commonality04_rotVSmirror01_MVPA_context.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa07_Commonality04_rotVSmirror01_MVPA_context.m`: dataset_root=1
- `pipeline-a/decoding/Step3_mvpa08_FourDirection1_MVPA.m`: dataset_root=1
- `pipeline-b/decoding/Step3_mvpa08_FourDirection1_MVPA.m`: dataset_root=1
- `pipeline-b/scripts/ArmB_stage_inputs.m`: dataset_root=1, spm_install=1
- `pipeline-b/scripts/ArmB_firstlevel_glm.m`: dataset_root=1, spm_install=1
- `pipeline-b/scripts/ArmB_validate_firstlevel.m`: dataset_root=1, spm_install=1
- `pipeline-b/scripts/Arm_common_mask_spm.m`: dataset_root=1, spm_install=1
- `pipeline-b/scripts/run_stage_inputs.sh`: dataset_root=1
- `pipeline-b/scripts/run_firstlevel_cohort.sh`: dataset_root=2
- `pipeline-b/scripts/setup_contract_decoding.sh`: dataset_root=3, spm_install=1
- `pipeline-b/scripts/run_contract_decoding_cohort.sh`: dataset_root=1
- `pipeline-b/scripts/normalize_contract_maps.m`: dataset_root=1, spm_install=1
- `shared/preprocessing/run_fastsurfer_ds004562.sh`: dataset_root=1, container_root=1, license_path=1, container_mount_paths=7, container_internal_paths=3
- `shared/preprocessing/run_fmriprep_ds004562.sh`: dataset_root=1, container_root=1, license_path=1, disabled_path=1, container_mount_paths=9, container_internal_paths=6
- `shared/preprocessing/verify_fastsurfer_ds004562.sh`: dataset_root=1
- `shared/preprocessing/cohort_runs_20260924.md`: launcher_root=1; all host/container paths in the summary were written directly as placeholders.

The three launcher copies came from `<NEURO_BIN>`, outside the project tree.
The source paths and container-internal paths above were replaced with
`<DATA_ROOT>`, `<CONTAINER_ROOT>`, `<NEURO_BIN>`, `<FREESURFER_LICENSE>`, and
explicit container-mount placeholders. No account, host, IP, or credential
material was present.
- `pipeline-b/scripts/build_common_masks.sh`: dataset_root=3, fsl_install=2
- `pipeline-b/scripts/build_group_support_masks.sh`: dataset_root=1, fsl_install=1
- `shared/setup_contract_decoding.sh`: dataset_root=3, spm_install=1
- `pipeline-c/scripts/build_mvpa_glm.py`: dataset_root=1, scratch=1
- `pipeline-c/scripts/run_searchlight.py`: dataset_root=1
- `pipeline-c/scripts/run_cohort.sh`: dataset_root=1, python_env=1
- `pipeline-c/scripts/run_context_searchlight_branch3_final_20260909.py`: dataset_root=1
- `pipeline-c/scripts/run_remaining_searchlights_stage2_20260909.py`: dataset_root=1
- `pipeline-c/scripts/run_preparation_searchlights_stage2_20260910.py`: dataset_root=1
- `pipeline-c/scripts/refit_preparation_betas_20260916.py`: dataset_root=1, scratch=1
- `pipeline-c/scripts/normalize_arm_c.py`: dataset_root=1
- `pipeline-c/scripts/normalize_arm_c_branches34_20260909.py`: dataset_root=1
- `pipeline-c/scripts/normalize_arm_c_noncv_20260910.py`: dataset_root=1
- `pipeline-c/scripts/normalize_arm_c_fourdirection_20260910.py`: dataset_root=1
- `pipeline-c/scripts/normalize_arm_c_prep_20260916.py`: dataset_root=1
- `pipeline-c/scripts/compute_core_consistency.py`: dataset_root=1
- `pipeline-c/scripts/compute_core_consistency_branches34_20260909.py`: dataset_root=1
- `pipeline-c/scripts/compute_core_consistency_noncv_20260910.py`: dataset_root=1
- `pipeline-c/scripts/compute_core_consistency_fourdirection_20260910.py`: dataset_root=1
- `pipeline-c/scripts/compute_fixed_mask_agreement_preparation_20260916.py`: dataset_root=1
- `pipeline-c/scripts/run_branch3_cohort_final_20260909.sh`: dataset_root=2, python_env=1
- `pipeline-c/scripts/run_branch4_remaining_final_20260909.sh`: dataset_root=2, python_env=1
- `pipeline-c/scripts/run_taskcontext_posneg90s_remaining_20260909.sh`: dataset_root=2, python_env=1
- `pipeline-c/scripts/run_taskcontext_rotationVSmirror_remaining_20260910.sh`: dataset_root=2, python_env=1
- `pipeline-c/scripts/run_fourdirection_mirror_remaining_20260910.sh`: dataset_root=2, python_env=1
- `pipeline-c/scripts/run_fourdirection_rot_neg90_remaining_20260910.sh`: dataset_root=2, python_env=1
- `pipeline-c/scripts/run_fourdirection_rot_pos90_remaining_20260910.sh`: dataset_root=2, python_env=1
- `pipeline-b/preprocessing/fmriprep.toml`: container_path=12
- `pipeline-c/preprocessing/fmriprep.toml`: container_path=12
- `pipeline-a/group/prepare_arm_a_tfce_reconstruction.m`: dataset_root=1
- `pipeline-a/group/run_arm_a_tfce_reconstruction.sh`: dataset_root=1, fsl_install=1
- `pipeline-c/scripts/normalize_arm_c_noncv_20260910.py`: ants_install=1
- `pipeline-c/scripts/normalize_arm_c_prep_20260916.py`: ants_install=1
- `pipeline-c/scripts/normalize_arm_c_fourdirection_20260910.py`: ants_install=1
- `pipeline-c/scripts/normalize_arm_c_branches34_20260909.py`: ants_install=1
- `pipeline-c/scripts/normalize_arm_c.py`: ants_install=1
- `pipeline-b/scripts/build_group_support_masks.sh`: ants_install=1
- `pipeline-b/scripts/build_common_masks.sh`: ants_install=1
- `pipeline-b/scripts/normalize_contract_maps.m`: ants_install=1
