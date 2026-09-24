# Publishable analysis code manifest

This bundle collects the analysis code used for pipelines A, B, and C. It contains no partner-laboratory pipeline code and no data. Paths were replaced by explicit placeholders. The frozen cohort is defined in `shared/subject_manifest.json`.

## Pipeline A

Order: `InitializeForAnalysis.m`; `Step2_fmri01_CopyFiles.m`; `Step2_fmri02_Preprocess.m`; `Step2_fmri03_UploadFiles_CONN_and_PreprocessART.m`; `Step2_fmri04_1stLevelAnalysis.m`; `Step3_mvpa01_1stLevelAnalysis.m`; the nine files in `decoding/`; matching normalization and SPM group scripts in `matlab/`; then the recorded FSL commands in `group-randomise/`. Inputs are BIDS images, events, and behavioral derivatives. Outputs are SPM-preprocessed images, first-level beta images, TDT native searchlight accuracy-minus-chance maps, normalized maps, and group statistics. The decoding files are the executed contract-mask copies, including cross-validation and label construction.

Recorded TFCE models exist for branches 1, 2, 3, 5, and 6 and the two Figure 10 regressions. No executed TFCE command/design was found for branch 4 or the three four-direction/commonality branches; none was reconstructed.

## Pipeline B

Order: FastSurfer/FMRIPrep preprocessing (`shared/preprocessing/`); `ArmB_stage_inputs.m`; `ArmB_firstlevel_glm.m`; `setup_contract_decoding.sh`; the nine files in `decoding/`; `normalize_contract_maps.m`; then recorded FSL commands in `group-randomise/`. Inputs are fMRIPrep T1w-space BOLD/confounds, events, behavioral derivatives, and explicit native masks. Outputs are staged/smoothed BOLD, SPM first-level betas, TDT maps, normalized maps, and group statistics. The executed fMRIPrep TOML and the three launch/verification scripts installed outside the project tree are included. Recorded TFCE models exist for branches 1, 2, 3, and 6 only.

## Pipeline C

Pipeline C shares Pipeline B preprocessing. Order: `shared/preprocessing/`; `build_mvpa_glm.py`; branch-specific searchlight scripts; preparation refit where applicable; matching `normalize_arm_c*.py`; consistency/group scripts; then recorded FSL commands in `group-randomise/`. Inputs are Pipeline B staged BOLD/confounds, events, behavioral derivatives, and masks. Outputs are Nilearn beta series, scikit-learn SVC searchlight maps, normalized/smoothed maps, agreement products, and group statistics. `build_mvpa_glm.py` is imported by the preparation refit, and the branch-3 searchlight module is imported by the remaining-branches driver; both dependencies are present. Recorded TFCE models exist for branches 1, 2, 3, and 6 only.

## Software provenance

- Operating system: Ubuntu 24.04.5 LTS; kernel 7.0.0-31-generic.
- MATLAB: R2025b (25.2), from project environment records.
- SPM: SPM12 r7771. The installation's `Contents.m` and `spm('Version')` identify the release as r7771; the `$Rev` tag embedded in `spm.m` is 7606 and is the revision of that individual source file, not the release identifier.
- CONN: 25.b. ART: bundled/used through CONN, release 7/19/11 (from `conn_reference_preproc.txt`).
- The Decoding Toolbox: 3.999I (2025-02-19, from its bundled `LOG.txt`); bundled LIBSVM 3.17.
- fMRIPrep: 25.2.5; Nipype 1.10.0; TemplateFlow 25.0.4.
- FastSurfer: 2.5.4 (`deepmi/fastsurfer:cu128-v2.5.4` recorded).
- Python: 3.12.13. NumPy 2.5.1; SciPy 1.18.0; pandas 3.0.5; nibabel 5.4.2; Nilearn 0.14.0; scikit-learn 1.8.0; h5py 3.16.0 (installed package metadata).
- FSL randomise: FSL 6.0.7.23.
- ANTs used for normalization: 2.6.4.post1-gdfadbfe (`antsRegistration --version`).

## Placeholders

`<DATA_ROOT>` is the dataset/project root; `<SPM12_ROOT>`, `<TDT_ROOT>`, `<CONN_ROOT>`, `<FSL_ROOT>`, and `<NEURO_BIN>` are software or launcher locations; `<BIDS_ROOT>`, `<OUTPUT_ROOT>`, `<WORK_ROOT>`, `<TEMPLATEFLOW_ROOT>`, `<FREESURFER_SUBJECTS_DIR>`, and `<FREESURFER_LICENSE>` are container mounts; `<SCRATCH_ROOT>` is optional disposable storage.

## Exclusions and gaps

Partner-laboratory material—including its MATLAB, PRT, VMP, and searchlight code—was deliberately excluded. Exploratory/broken Arm C prototypes, compiled Python caches, figures, data, results, and comparison-only scripts were excluded. The fMRIPrep/FastSurfer launchers were found outside the project tree and added under `shared/preprocessing/`; their cohort provenance is summarized in `shared/preprocessing/cohort_runs_20260924.md`. ART is the bundled release 7/19/11 recorded in CONN's reference file. TDT, h5py, and ANTs versions are now resolved.

## Re-check of previously reported provenance gaps

- Preprocessing launchers: resolved; installed under `<NEURO_BIN>/` outside the project tree, with sanitized copies included under `shared/preprocessing/`.
- TFCE coverage: the whole-machine inventory found preserved group tests for A branches 1, 2, 3, 5, 6 and the two Figure 10 regressions; B branches 1, 2, 3, 6; and C branches 1, 2, 3, 6. No randomise invocation or output for A branch 4, A branches 7–9, B/C branch 4, B/C branches 5 and 7–11, or any other missing branch was found. For those cells the run status is unknown: the available evidence cannot distinguish never run from run-but-not-preserved. No branch can be positively classified as run-but-not-preserved.
- Toolbox versions: resolved for TDT (3.999I), ART (7/19/11), ANTs (2.6.4.post1-gdfadbfe), and h5py (3.16.0).
- SPM conflict: resolved at release level as SPM12 r7771; `spm.m` contains an older source-file `$Rev: 7606` tag, so that tag is not treated as the release version.
