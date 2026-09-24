#!/usr/bin/env bash
#
# Run fMRIPrep on ds004562 via Apptainer. Run AS the analysis user. No sudo.
#
#   bash run_fmriprep_ds004562.sh 01          # one subject (do this first)
#   bash run_fmriprep_ds004562.sh 01 02 03    # several
#   bash run_fmriprep_ds004562.sh all         # all dataset subjects except sub-16
#
# Dataset facts that drive the flags below:
#   * no fmap/ anywhere      -> fieldmap-less SDC (--use-syn-sdc) is the only option
#   * ses-01pre is beh only  -> only ses-02fmri gets preprocessed
#   * SliceTiming present    -> slice-timing correction runs by default (TR 2.3s, 41 slices)
#   * sub-16 excluded by the authors (README: did not complete the MRI session)
#
set -euo pipefail

ACC=ds004562
SES=ses-02fmri                     # the only session with imaging data
ROOT="${OPENNEURO_DIR:-<DATA_ROOT>}"
BIDS="$ROOT/$ACC"
OUT="$ROOT/derivatives/fmriprep-$ACC"
WORK="$ROOT/work/$ACC"
TFLOW="$ROOT/.templateflow"
SIF="${FMRIPREP_SIF:-<CONTAINER_ROOT>/fmriprep-25.2.5.sif}"
LICENSE="${FS_LICENSE:-<FREESURFER_LICENSE>}"

# 24 cores / 125 GB on this box. Leave headroom for other users.
NPROCS="${NPROCS:-16}"
OMP_NTHREADS="${OMP_NTHREADS:-8}"
MEM_MB="${MEM_MB:-64000}"

# Surface handling: import complete FastSurfer results when present; otherwise
# skip surface reconstruction by default for this volumetric analysis.
#
# Verified against the source paper (Song et al. 2023, Front. Hum. Neurosci.
# 17:1221944): the published pipeline is entirely volumetric -- SPM12 for
# preprocessing, ART/CONN for outlier detection, The Decoding Toolbox + LIBSVM
# for MVPA, whole-brain searchlight (9 mm radius) in voxel space. The words
# "FreeSurfer", "cortical surface", "surface-based", "vertex", "fsaverage",
# "CIFTI" and "GIFTI" appear nowhere in the paper. recon-all would cost
# ~6-12 h/subject (~6-11 days for the cohort) and produce nothing this
# analysis consumes.
#
# Set FS_NO_RECONALL=0 if you later want surface-based analyses.
# Trade-off when disabled: BOLD->T1w coregistration falls back from FreeSurfer
# bbregister to FSL FLIRT with a BBR cost function on an ANTs-derived WM
# segmentation. Minor for 3 mm EPI, but it is a real difference.
FS_NO_RECONALL="${FS_NO_RECONALL:-1}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*"; exit 1; }

[ $# -ge 1 ] || die "usage: bash $0 <01 02 ...|all>"

if [ "$1" = "all" ]; then
    [ $# -eq 1 ] || die "'all' cannot be combined with explicit subject labels"
    mapfile -t SUBJECTS < <(
        find "$BIDS" -mindepth 1 -maxdepth 1 -type d -name 'sub-*' -printf '%f\n' 2>/dev/null \
            | sed 's/^sub-//' | grep -Ev '^16$' | sort -V
    )
else
    SUBJECTS=("$@")
fi

# ---------------------------------------------------------------- preflight
log "Preflight"
command -v apptainer >/dev/null || die "apptainer not installed (run provision_fmri_user.sh)"
[ -f "$SIF" ]      || die "container missing: $SIF"
[ -d "$BIDS" ]     || die "dataset missing: $BIDS  (run fetch_${ACC}.sh)"
[ -s "$LICENSE" ]  || die "FreeSurfer license missing: $LICENSE
    Get one free at https://surfer.nmr.mgh.harvard.edu/registration.html
    then: sudo install -m 0644 license.txt $LICENSE"
[ "${#SUBJECTS[@]}" -gt 0 ] || die "no eligible subjects found under $BIDS"
[[ "$NPROCS" =~ ^[1-9][0-9]*$ ]] || die "NPROCS must be a positive integer (got '$NPROCS')"
[[ "$OMP_NTHREADS" =~ ^[1-9][0-9]*$ ]] || die "OMP_NTHREADS must be a positive integer (got '$OMP_NTHREADS')"
[[ "$MEM_MB" =~ ^[1-9][0-9]*$ ]] || die "MEM_MB must be a positive integer (got '$MEM_MB')"
[[ "$FS_NO_RECONALL" =~ ^[01]$ ]] || die "FS_NO_RECONALL must be 0 or 1 (got '$FS_NO_RECONALL')"
for s in "${SUBJECTS[@]}"; do
    [[ "$s" =~ ^[A-Za-z0-9]+$ ]] || die "invalid subject label: '$s'"
    [ "$s" != "16" ] || die "sub-16 is excluded by the study protocol"
    [ -f "$BIDS/sub-$s/$SES/anat/sub-${s}_${SES}_T1w.nii.gz" ] \
        || die "sub-$s has no required T1w image"
    [ -f "$BIDS/sub-$s/$SES/func/sub-${s}_${SES}_task-adaptation_bold.nii.gz" ] \
        || die "sub-$s has no required adaptation BOLD image"
done

mkdir -p "$OUT" "$WORK" "$TFLOW"
echo "  subjects : ${SUBJECTS[*]}"
echo "  bids     : $BIDS"
echo "  output   : $OUT"
echo "  work     : $WORK   (transient, can be large - delete when done)"
echo "  resources: --nprocs $NPROCS --omp-nthreads $OMP_NTHREADS --mem-mb $MEM_MB"
df -h "$ROOT" | tail -1 | awk '{print "  free     : "$4" on "$6}'

# --- surface source: FastSurfer > built-in recon-all > none ------------------
# fMRIPrep cannot call FastSurfer itself. If run_fastsurfer_ds004562.sh has
# already produced a FreeSurfer-layout SUBJECTS_DIR, import it with
# --fs-subjects-dir + --fs-no-resume ("import pre-computed reconstruction
# without resuming" -- without it fMRIPrep tries to continue recon-all and the
# time saving is lost).
FSDIR="${FASTSURFER_DIR:-$ROOT/derivatives/fastsurfer}"
EXTRA=(); FSBIND=()

# Two naming subtleties, both learned the hard way on sub-01:
#  * recon-surf.done, not recon-all.done -- FastSurfer calls FreeSurfer's
#    recon-all for intermediate steps and recon-all writes recon-all.done
#    itself, so it can appear mid-run and be misread as a finished recon.
#  * sub-<label>_<session>, not sub-<label> -- the T1w sits under a session, so
#    sMRIPrep does session-wise anatomical processing and asks for FreeSurfer
#    subject "sub-01_ses-02fmri". A plain "sub-01" directory is silently not
#    found: get_surfaces returns nothing and the midthickness MapNode dies with
#    "Input in_file was not set but it is listed in iterfields".
NRECON=0
for s in "${SUBJECTS[@]}"; do
    [ -f "$FSDIR/sub-${s}_${SES}/scripts/recon-surf.done" ] && NRECON=$((NRECON + 1))
done

if [ "$NRECON" -gt 0 ] && [ "$NRECON" -eq "${#SUBJECTS[@]}" ]; then
    EXTRA+=(--fs-subjects-dir "<FREESURFER_SUBJECTS_CONTAINER_ROOT>" --fs-no-resume)
    FSBIND=(-B "$FSDIR":"<FREESURFER_SUBJECTS_CONTAINER_ROOT>")
    echo "  surfaces  : FastSurfer, importing $NRECON/${#SUBJECTS[@]} from $FSDIR"
elif [ "$NRECON" -gt 0 ]; then
    die "FastSurfer recon exists for only $NRECON of ${#SUBJECTS[@]} requested subjects.
    Importing a partial SUBJECTS_DIR makes fMRIPrep silently run recon-all for
    the rest (~6-12 h each). Finish them first:
        run_fastsurfer_${ACC}.sh ${SUBJECTS[*]}
    or force the surface-free path:
        FASTSURFER_DIR=<DISABLED_FASTSURFER_DIR> $0 ${SUBJECTS[*]}"
elif [ "$FS_NO_RECONALL" = "1" ]; then
    EXTRA+=(--fs-no-reconall)
    echo "  surfaces  : none (--fs-no-reconall) - paper's MVPA is volumetric"
else
    echo "  surfaces  : fMRIPrep recon-all - adds roughly 6-12 h per subject"
fi

# ---------------------------------------------------------------- run
log "Running fMRIPrep"
# --cleanenv keeps the host environment out of the container.
# TEMPLATEFLOW_HOME is shared so templates are downloaded once, not per user.
APPTAINERENV_TEMPLATEFLOW_HOME="<TEMPLATEFLOW_CONTAINER_ROOT>" \
apptainer run --cleanenv \
    -B "$BIDS":"<BIDS_CONTAINER_ROOT>":ro \
    -B "$OUT":"<DERIVATIVES_CONTAINER_ROOT>" \
    -B "$WORK":"<WORK_CONTAINER_ROOT>" \
    -B "$TFLOW":"<TEMPLATEFLOW_CONTAINER_ROOT>" \
    -B "$LICENSE":"<FREESURFER_LICENSE_CONTAINER>":ro \
    "${FSBIND[@]}" \
    "$SIF" \
    "<BIDS_CONTAINER_ROOT>" "<DERIVATIVES_CONTAINER_ROOT>" participant \
    --participant-label "${SUBJECTS[@]}" \
    --fs-license-file "<FREESURFER_LICENSE_CONTAINER>" \
    -w "<WORK_CONTAINER_ROOT>" \
    --output-spaces MNI152NLin2009cAsym:res-2 T1w \
    --use-syn-sdc warn \
    --nprocs "$NPROCS" \
    --omp-nthreads "$OMP_NTHREADS" \
    --mem-mb "$MEM_MB" \
    --notrack \
    "${EXTRA[@]}"

# --output-spaces: T1w (native) kept because MVPA usually decodes in native
#   space on unsmoothed data; MNI152NLin2009cAsym:res-2 for group results.
#   fMRIPrep does not smooth -- do that downstream if your analysis needs it.
# --use-syn-sdc warn: no fieldmaps in this dataset, so use fieldmap-less SDC
#   and warn rather than fail if it cannot be applied.

log "Done"
echo "  reports: $OUT/sub-*.html   <- open these and check registration quality"
echo "  work dir $WORK can be deleted once you are satisfied with the output"
