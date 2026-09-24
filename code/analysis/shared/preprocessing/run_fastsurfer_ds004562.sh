#!/usr/bin/env bash
#
# FastSurfer surface reconstruction for ds004562, producing a FreeSurfer-layout
# SUBJECTS_DIR that fMRIPrep then consumes via --fs-subjects-dir.
# Run AS the analysis user. No sudo.
#
#   run_fastsurfer_ds004562.sh 01           # one subject
#   run_fastsurfer_ds004562.sh all          # all dataset subjects except sub-16
#   JOBS=4 run_fastsurfer_ds004562.sh all   # 4 concurrent subjects
#
# Why FastSurfer rather than fMRIPrep's built-in recon-all:
#   recon-all is ~6-12 h/subject; FastSurfer is ~1-2 h. fMRIPrep has no
#   --use-fastsurfer flag, so the supported integration is to build the
#   SUBJECTS_DIR here first and hand it over with --fs-subjects-dir.
#
# NOTE the source paper's MVPA (Song et al. 2023) is purely volumetric and uses
# no surfaces at all. Surfaces are still worth having here for: bbregister
# BOLD->T1w coregistration (better than the FLIRT-BBR fallback), aparc+aseg
# anatomical ROIs, and better tissue masks for aCompCor confounds.
#
set -euo pipefail

ACC=ds004562
SES=ses-02fmri                     # the only session with imaging data
ROOT="${OPENNEURO_DIR:-<DATA_ROOT>}"
BIDS="$ROOT/$ACC"
SUBJECTS_DIR="$ROOT/derivatives/fastsurfer"
SIF="${FASTSURFER_SIF:-<CONTAINER_ROOT>/fastsurfer-cu128-v2.5.4.sif}"
LICENSE="${FS_LICENSE:-<FREESURFER_LICENSE>}"

THREADS="${THREADS:-8}"            # per subject
JOBS="${JOBS:-2}"                  # concurrent subjects; 24 cores on this box
INTERVAL="${INTERVAL:-30}"         # progress refresh, seconds
STREAM="${STREAM:-0}"              # 1 = pass FastSurfer's raw output through

# Completion marker. recon-surf.sh writes scripts/recon-surf.done only after
# "finished without error" (recon-surf.sh:392). Do NOT use recon-all.done:
# FastSurfer calls FreeSurfer's recon-all for intermediate steps and recon-all
# writes that file itself, so it can appear mid-run and be read as "complete".
DONE_MARKER=scripts/recon-surf.done

# FreeSurfer subject ID != BIDS subject label for this dataset.
# The T1w lives under a session (sub-01/ses-02fmri/anat/), so sMRIPrep performs
# session-wise anatomical processing and looks for a FreeSurfer subject named
# "sub-<label>_ses-<session>". Naming the FastSurfer output plain "sub-01" makes
# fMRIPrep's get_surfaces find nothing, and the midthickness MapNode then dies
# with "Input in_file was not set but it is listed in iterfields" -- verified on
# sub-01, where fs_base_inputs requested subject_id sub-01_ses-02fmri.
fsid_of() { echo "sub-$1_$SES"; }

# Ordered progress milestones, verified against a live run. Each entry is
# <relative path>|<label>.
MILESTONES=(
    "mri/orig.mgz|conform input"
    "mri/aparc.DKTatlas+aseg.deep.mgz|deep segmentation (GPU)"
    "mri/mask.mgz|brain mask"
    "mri/brain.finalsurfs.mgz|intensity normalization"
    "surf/lh.orig.premesh|tessellation"
    "surf/lh.qsphere.nofix|topology prep"
    "surf/lh.white.preaparc|white preaparc"
    "surf/rh.white|white surfaces"
    "surf/rh.pial|pial surfaces"
    "surf/rh.thickness|thickness"
    "label/rh.aparc.DKTatlas.annot|parcellation"
    "$DONE_MARKER|complete"
)

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*"; exit 1; }

[ $# -ge 1 ] || die "usage: $0 <01 02 ...|all>"
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
command -v apptainer >/dev/null || die "apptainer not installed"
[ -f "$SIF" ]     || die "container missing: $SIF  (re-run provision_fmri_user.sh)"
[ -d "$BIDS" ]    || die "dataset missing: $BIDS  (run fetch_$ACC.sh)"
[ -s "$LICENSE" ] || die "FreeSurfer license missing: $LICENSE
    FastSurfer's surface pipeline uses FreeSurfer binaries and needs it too."
[ "${#SUBJECTS[@]}" -gt 0 ] || die "no eligible subjects found under $BIDS"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "THREADS must be a positive integer (got '$THREADS')"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer (got '$JOBS')"
[[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]] || die "INTERVAL must be a positive integer (got '$INTERVAL')"
[[ "$STREAM" =~ ^[01]$ ]] || die "STREAM must be 0 or 1 (got '$STREAM')"
for s in "${SUBJECTS[@]}"; do
    [[ "$s" =~ ^[A-Za-z0-9]+$ ]] || die "invalid subject label: '$s'"
    [ "$s" != "16" ] || die "sub-16 is excluded by the study protocol"
    [ -f "$BIDS/sub-$s/$SES/anat/sub-${s}_${SES}_T1w.nii.gz" ] \
        || die "sub-$s has no required T1w image"
done

# GPU is optional. This box's driver has been down (kernel module flavour
# mismatch, see fix_nvidia_driver.sh) -- fall back to CPU rather than failing.
GPU_AVAILABLE=0
if nvidia-smi -L >/dev/null 2>&1; then
    GPU_AVAILABLE=1
    DEVICE=cuda; NV_FLAG=(--nv)
    VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    echo "  device   : cuda ($(nvidia-smi --query-gpu=name --format=csv,noheader | head -1), ${VRAM} MiB)"
    # Only the segmentation phase uses the GPU (~5-7 GB); the surface phase is
    # CPU-bound. Concurrent subjects therefore contend for VRAM in bursts.
    if [ "$JOBS" -gt 2 ] && [ "$VRAM" -lt 24000 ]; then
        warn "JOBS=$JOBS on a ${VRAM} MiB card risks CUDA OOM during segmentation."
        warn "Recommend JOBS<=2 here, or JOBS=$JOBS with DEVICE forced to cpu."
    fi
else
    DEVICE=cpu;  NV_FLAG=()
    warn "no usable GPU -- running on CPU (slower). Fix with fix_nvidia_driver.sh."
    echo "  device   : cpu"
fi
# Escape hatch: FASTSURFER_DEVICE=cpu forces CPU even when a GPU is present.
DEVICE="${FASTSURFER_DEVICE:-$DEVICE}"
case "$DEVICE" in
    cpu) NV_FLAG=() ;;
    cuda)
        [ "$GPU_AVAILABLE" -eq 1 ] || die "FASTSURFER_DEVICE=cuda but nvidia-smi cannot access a GPU"
        NV_FLAG=(--nv)
        ;;
    *) die "FASTSURFER_DEVICE must be 'cpu' or 'cuda' (got '$DEVICE')" ;;
esac

mkdir -p "$SUBJECTS_DIR"
echo "  subjects : ${SUBJECTS[*]}"
echo "  output   : $SUBJECTS_DIR"
echo "  parallel : $JOBS subject(s) x $THREADS threads"
df -h "$ROOT" | tail -1 | awk '{print "  free     : "$4" on "$6}'

# ---------------------------------------------------------------- run one
run_one() {
    local s="$1"
    local sid="sub-$s"                 # BIDS label, used for input paths
    local fsid; fsid=$(fsid_of "$s")   # FreeSurfer subject id, used for output
    local t1="$BIDS/$sid/$SES/anat/${sid}_${SES}_T1w.nii.gz"

    if [ ! -f "$t1" ]; then
        warn "$sid: no T1w at $t1 -- skipped"
        return 0
    fi
    if [ -f "$SUBJECTS_DIR/$fsid/$DONE_MARKER" ]; then
        echo "  $fsid: already reconstructed, skipping"
        return 0
    fi

    local cmd=(
        apptainer exec --cleanenv "${NV_FLAG[@]}"
            -B "$BIDS":"<BIDS_CONTAINER_ROOT>":ro
            -B "$SUBJECTS_DIR":"<OUTPUT_CONTAINER_ROOT>"
            -B "$LICENSE":"<FREESURFER_LICENSE_CONTAINER>":ro
            "$SIF"
            "<FASTSURFER_CONTAINER_ROOT>/run_fastsurfer.sh"
                --t1 "<BIDS_CONTAINER_ROOT>/$sid/$SES/anat/${sid}_${SES}_T1w.nii.gz"
                --sid "$fsid"
                --sd "<OUTPUT_CONTAINER_ROOT>"
                --fs_license "<FREESURFER_LICENSE_CONTAINER>"
                --device "$DEVICE"
                --threads "$THREADS"
                --parallel
                --3T
    )
    local rc
    if [ "$STREAM" = "1" ]; then
        "${cmd[@]}" 2>&1 | tee "$SUBJECTS_DIR/${fsid}.log"
        rc=${PIPESTATUS[0]}
    else
        "${cmd[@]}" > "$SUBJECTS_DIR/${fsid}.log" 2>&1
        rc=$?
    fi
    [ "$rc" -eq 0 ] || { warn "$fsid: FAILED (rc=$rc) -- see $SUBJECTS_DIR/${fsid}.log"; return 1; }
    [ -f "$SUBJECTS_DIR/$fsid/$DONE_MARKER" ] \
        || { warn "$fsid: exited 0 but $DONE_MARKER missing -- treat as incomplete"; return 1; }
}

# ---------------------------------------------------------------- progress
# How far along is one subject: "<n>/<total> <label>"
milestone_of() {
    local sid="$1" n=0 label="starting"
    local m path lab
    for m in "${MILESTONES[@]}"; do
        path="${m%%|*}"; lab="${m##*|}"
        if [ -e "$SUBJECTS_DIR/$sid/$path" ]; then n=$((n + 1)); label="$lab"; fi
    done
    printf '%d/%d %s' "$n" "${#MILESTONES[@]}" "$label"
}

# Current named stage, from FreeSurfer's "#@# <Stage> <date>" markers.
# recon-all-status.log first: it keeps updating through the parallel-hemisphere
# phase, whereas recon-surf.log stops at "Fill" once RunBatchJobs forks the
# per-hemisphere jobs (verified on a live run).
stage_of() {
    local d="$SUBJECTS_DIR/$1/scripts" log
    for log in "$d/recon-all-status.log" "$d/recon-surf.log"; do
        [ -f "$log" ] || continue
        local m
        m=$(grep -a '^#@# ' "$log" 2>/dev/null | tail -1 \
            | sed -E 's/^#@# //; s/ [A-Z][a-z]{2} [A-Z][a-z]{2} .*$//' | cut -c1-28)
        [ -n "$m" ] && { echo "$m"; return; }
    done
    echo "segmentation"
}

hms() { printf '%02d:%02d:%02d' $(($1/3600)) $((($1%3600)/60)) $(($1%60)); }

monitor() {
    local start_epoch="$1"; shift
    local tty=0; [ -t 1 ] && tty=1
    local first=1
    while [ -e "$RUNFLAG" ]; do
        sleep "$INTERVAL"
        [ -e "$RUNFLAG" ] || break
        local el; el=$(hms $(($(date +%s) - start_epoch)))
        if [ "$tty" = 1 ] && [ "$first" = 0 ]; then
            printf '\033[%dA' "${#SUBJECTS[@]}"      # redraw in place
        fi
        first=0
        local s
        for s in "${SUBJECTS[@]}"; do
            if [ -f "$SUBJECTS_DIR/$(fsid_of "$s")/$DONE_MARKER" ]; then
                printf '\033[K  [%s] sub-%-3s done\n' "$el" "$s"
            elif [ -d "$SUBJECTS_DIR/$(fsid_of "$s")" ]; then
                printf '\033[K  [%s] sub-%-3s %-30s %s\n' \
                    "$el" "$s" "$(stage_of "$(fsid_of "$s")")" "$(milestone_of "$(fsid_of "$s")")"
            else
                printf '\033[K  [%s] sub-%-3s queued\n' "$el" "$s"
            fi
        done
    done
}

# --3T selects the 3T atlas for Talairach registration. This dataset is a
# Siemens Verio 3T (MagneticFieldStrength: 3 in the BOLD sidecar).

# ---------------------------------------------------------------- dispatch
log "Running FastSurfer"
RUNFLAG=$(mktemp); START_EPOCH=$(date +%s); MONPID=""; PIDS=()
cleanup() { rm -f "$RUNFLAG"; [ -n "$MONPID" ] && kill "$MONPID" 2>/dev/null; return 0; }
on_signal() {
    warn "interrupted; stopping ${#PIDS[@]} reconstruction job(s)"
    local p
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
    exit 130
}
trap cleanup EXIT
trap on_signal INT TERM

if [ "$STREAM" = "1" ]; then
    echo "  STREAM=1: FastSurfer output passed through (also saved to <sid>.log)"
else
    echo "  progress every ${INTERVAL}s -- STREAM=1 for raw output, or:"
    echo "    tail -f $SUBJECTS_DIR/sub-<id>_$SES/scripts/recon-surf.log"
    monitor "$START_EPOCH" & MONPID=$!
fi

# Count only reconstruction jobs. `jobs -rp` would also count the monitor and
# silently shrink the pool by one.
running_count() { local n=0 p; for p in "${PIDS[@]}"; do kill -0 "$p" 2>/dev/null && n=$((n + 1)); done; echo "$n"; }

for s in "${SUBJECTS[@]}"; do
    while [ "$(running_count)" -ge "$JOBS" ]; do sleep 2; done
    run_one "$s" & PIDS+=($!)
done
for p in "${PIDS[@]}"; do wait "$p" || true; done
cleanup; MONPID=""

# ---------------------------------------------------------------- summary
log "Summary"
# Derive success from the completion marker rather than from a variable set
# inside a backgrounded subshell -- `cmd || FAILED+=(x) &` loses the assignment.
DONE=0; FAILED=()
for s in "${SUBJECTS[@]}"; do
    if [ -f "$SUBJECTS_DIR/$(fsid_of "$s")/$DONE_MARKER" ]; then
        DONE=$((DONE + 1))
    else
        FAILED+=("$(fsid_of "$s")")
    fi
done
echo "  reconstructed: $DONE / ${#SUBJECTS[@]}  ($(hms $(($(date +%s) - START_EPOCH))) elapsed)"
[ ${#FAILED[@]} -eq 0 ] || warn "incomplete: ${FAILED[*]}"

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "  FastSurfer did not complete every requested subject; fMRIPrep was not declared ready."
    exit 1
fi

cat <<EOF

SUBJECTS_DIR ready: $SUBJECTS_DIR

fMRIPrep will pick this up automatically -- run_fmriprep_${ACC}.sh detects the
directory and switches from --fs-no-reconall to --fs-subjects-dir:

  run_fmriprep_${ACC}.sh 01
EOF
