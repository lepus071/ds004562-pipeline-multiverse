# Cohort preprocessing provenance

These summaries are derived from the preserved cohort logs and the launchers
installed outside the project tree in `<NEURO_BIN>/`. Host and container
paths are represented by the publication placeholders used in this bundle.

## FastSurfer

- Version: FastSurfer 2.5.4; image `deepmi/fastsurfer:cu128-v2.5.4` (local SIF: `<CONTAINER_ROOT>/fastsurfer-cu128-v2.5.4.sif`).
- Participants: 22 (`sub-01`..`sub-23`, excluding `sub-16`).
- Date range: 2026-08-04 10:17–17:56 (log birth/last modification).
- Wrapper command: `run_fastsurfer_ds004562.sh all`.
- Expanded command: `apptainer exec --cleanenv [--nv when CUDA was available] -B <DATA_ROOT>/ds004562:/data:ro -B <DATA_ROOT>/derivatives/fastsurfer:/output -B <FREESURFER_LICENSE>:/fs_license.txt:ro <CONTAINER_ROOT>/fastsurfer-cu128-v2.5.4.sif /fastsurfer/run_fastsurfer.sh --t1 /data/sub-<id>/ses-02fmri/anat/sub-<id>_ses-02fmri_T1w.nii.gz --sid sub-<id>_ses-02fmri --sd /output --fs_license /fs_license.txt --device <cpu-or-cuda> --threads 8 --parallel --3T`.

## fMRIPrep

- Version: fMRIPrep 25.2.5 (log); Nipype 1.10.0 and TemplateFlow 25.0.4 are also recorded.
- Image: local SIF `<CONTAINER_ROOT>/fmriprep-25.2.5.sif`.
- Participants: 22 (`sub-01`..`sub-23`, excluding `sub-16`).
- Date range: 2026-08-30 12:05–2026-08-31 00:57 (cohort log).
- Wrapper command: `run_fmriprep_ds004562.sh all`.
- Expanded command: `apptainer run --cleanenv -B <DATA_ROOT>/ds004562:/data:ro -B <DATA_ROOT>/derivatives/fmriprep-ds004562:/out -B <DATA_ROOT>/work/ds004562:/work -B <DATA_ROOT>/.templateflow:/templateflow -B <DATA_ROOT>/derivatives/fastsurfer:/fsdir -B <FREESURFER_LICENSE>:/fs_license.txt:ro <CONTAINER_ROOT>/fmriprep-25.2.5.sif /data /out participant --participant-label <22 subjects> --fs-license-file /fs_license.txt -w /work --output-spaces MNI152NLin2009cAsym:res-2 T1w --use-syn-sdc warn --nprocs 16 --omp-nthreads 8 --mem-mb 64000 --notrack --fs-subjects-dir /fsdir --fs-no-resume`.

The original interactive shell invocation is not preserved as a transcript;
the wrapper commands above are the cohort invocations established by the
launcher documentation and the 22-subject preflight/completion records.
