#!/usr/bin/env bash
#
# QC for FastSurfer output on ds004562. Run AS the analysis user. No sudo.
#
#   verify_fastsurfer_ds004562.sh 01        # one subject
#   verify_fastsurfer_ds004562.sh all       # whole cohort
#
# Two layers:
#   1. file completeness -- FastSurfer's actual filenames, NOT FreeSurfer's.
#      FastSurfer parcellates with the DKT atlas and never writes the classic
#      Desikan-Killiany label/?h.aparc.annot or stats/?h.aparc.stats. Checking
#      for those reports a false failure on every subject.
#   2. quantitative sanity -- a run can finish cleanly and still be garbage.
#      Ranges are anchored on sub-01 (25F): MeanThickness 2.58 mm both hemis,
#      NumVert ~118-120k, eTIV 1.31e6 mm^3, BrainSegVol-to-eTIV 0.853.
#
# Exit status: 0 if every requested subject passes, 1 otherwise.
#
set -uo pipefail

SES=ses-02fmri                 # the only session with imaging data
ROOT="${OPENNEURO_DIR:-<DATA_ROOT>}"
SUBJECTS_DIR="${FASTSURFER_DIR:-$ROOT/derivatives/fastsurfer}"

# Plausible ranges for healthy adults. Deliberately wide -- these catch gross
# failure (one hemisphere collapsed, skull left in the mask), not subtle bias.
TH_MIN=2.0   ; TH_MAX=3.2      # mean cortical thickness, mm
VERT_MIN=80000 ; VERT_MAX=200000
ETIV_MIN=1000000 ; ETIV_MAX=2100000
ASYM_MAX=0.30                  # |lh-rh| mean thickness, mm

REQUIRED=(
    mri/orig.mgz mri/T1.mgz mri/brainmask.mgz mri/aseg.mgz mri/aparc+aseg.mgz mri/wm.mgz
    surf/lh.white surf/rh.white surf/lh.pial surf/rh.pial
    surf/lh.inflated surf/rh.inflated surf/lh.sphere.reg surf/rh.sphere.reg
    surf/lh.curv surf/rh.curv surf/lh.sulc surf/rh.sulc
    surf/lh.thickness surf/rh.thickness
    label/lh.cortex.label label/rh.cortex.label
    label/lh.aparc.DKTatlas.annot label/rh.aparc.DKTatlas.annot
    stats/aseg.stats stats/lh.aparc.DKTatlas.mapped.stats stats/rh.aparc.DKTatlas.mapped.stats
    scripts/recon-surf.done
)

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
bad()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m%s\033[0m\n' "$*"; }

[ $# -ge 1 ] || { echo "usage: $0 <01 02 ...|all>"; exit 2; }
if [ "$1" = "all" ]; then
    [ $# -eq 1 ] || { echo "'all' cannot be combined with explicit subject labels"; exit 2; }
    BIDS="$ROOT/ds004562"
    mapfile -t SUBJECTS < <(
        find "$BIDS" -mindepth 1 -maxdepth 1 -type d -name 'sub-*' -printf '%f\n' 2>/dev/null \
            | sed 's/^sub-//' | grep -Ev '^16$' | sort -V
    )
else
    SUBJECTS=("$@")
fi
[ "${#SUBJECTS[@]}" -gt 0 ] || { echo "no eligible subjects found"; exit 2; }
for s in "${SUBJECTS[@]}"; do
    [[ "$s" =~ ^[A-Za-z0-9]+$ ]] || { echo "invalid subject label: '$s'"; exit 2; }
    [ "$s" != "16" ] || { echo "sub-16 is excluded by the study protocol"; exit 2; }
done

# measure <stats-file> <short-name>
# Rows look like: "# Measure <Name>, <ShortName>, <Description>, <value>, <unit>"
# Match field 2 exactly. A substring match on "eTIV" also hits
# "# Measure BrainSegVol-to-eTIV, ..., Ratio of BrainSegVol to eTIV, 0.853, unitless"
# and silently returns the ratio instead of the volume.
measure() {
    awk -F', *' -v metric_key="$2" '/^# Measure / && $2 == metric_key { print $(NF-1); exit }' "$1" 2>/dev/null
}

# numeric comparison without bc (not installed by default in a bare env)
fcmp() { awk -v a="$1" -v b="$2" "BEGIN{exit !(a $3 b)}"; }

log "FastSurfer QC -- $SUBJECTS_DIR"
printf '  %-8s %-6s %-14s %-14s %-11s %s\n' SUBJ STATUS "THICK lh/rh" "VERT lh/rh" "eTIV" NOTES

FAILED=()
for s in "${SUBJECTS[@]}"; do
    # sMRIPrep names session-wise anatomical recons sub-<label>_ses-<session>,
    # so that is what FastSurfer wrote and what fMRIPrep will look for.
    sid="sub-${s}_${SES}"
    S="$SUBJECTS_DIR/$sid"
    notes=(); status=OK

    if [ ! -d "$S" ]; then
        printf '  %-8s ' "$sid"; bad "MISSING  (not reconstructed)"
        FAILED+=("$sid"); continue
    fi

    # --- layer 1: file completeness -----------------------------------------
    miss=()
    for f in "${REQUIRED[@]}"; do
        [ -s "$S/$f" ] || miss+=("$f")
    done
    if [ ${#miss[@]} -gt 0 ]; then
        status=FAIL; notes+=("missing ${#miss[@]} file(s)")
    fi

    # --- layer 2: quantitative sanity ---------------------------------------
    lt=$(measure "$S/stats/lh.aparc.DKTatlas.mapped.stats" MeanThickness)
    rt=$(measure "$S/stats/rh.aparc.DKTatlas.mapped.stats" MeanThickness)
    lv=$(measure "$S/stats/lh.aparc.DKTatlas.mapped.stats" NumVert)
    rv=$(measure "$S/stats/rh.aparc.DKTatlas.mapped.stats" NumVert)
    et=$(measure "$S/stats/aseg.stats" eTIV)

    for pair in "lh:$lt" "rh:$rt"; do
        h=${pair%%:*}; v=${pair#*:}
        [ -n "$v" ] || { status=FAIL; notes+=("$h thickness unreadable"); continue; }
        fcmp "$v" "$TH_MIN" '>=' && fcmp "$v" "$TH_MAX" '<=' \
            || { status=FAIL; notes+=("$h thickness $v outside $TH_MIN-$TH_MAX"); }
    done
    for pair in "lh:$lv" "rh:$rv"; do
        h=${pair%%:*}; v=${pair#*:}
        [ -n "$v" ] || { status=FAIL; notes+=("$h vertices unreadable"); continue; }
        fcmp "$v" "$VERT_MIN" '>=' && fcmp "$v" "$VERT_MAX" '<=' \
            || { status=FAIL; notes+=("$h vertices $v outside $VERT_MIN-$VERT_MAX"); }
    done
    if [ -n "$et" ]; then
        fcmp "$et" "$ETIV_MIN" '>=' && fcmp "$et" "$ETIV_MAX" '<=' \
            || { status=FAIL; notes+=("eTIV $et outside range"); }
    else
        status=FAIL; notes+=("eTIV unreadable")
    fi
    # A collapsed hemisphere usually shows up as asymmetry, not as an out-of-range value.
    if [ -n "$lt" ] && [ -n "$rt" ]; then
        asym=$(awk -v a="$lt" -v b="$rt" 'BEGIN{d=a-b; print (d<0?-d:d)}')
        fcmp "$asym" "$ASYM_MAX" '<=' \
            || { status=FAIL; notes+=("lh/rh thickness asymmetry $asym mm"); }
    fi

    printf '  %-8s ' "$sid"
    if [ "$status" = OK ]; then printf '\033[0;32m%-6s\033[0m ' OK
    else printf '\033[1;31m%-6s\033[0m ' FAIL; FAILED+=("$sid"); fi
    printf '%-14s %-14s %-11s %s\n' \
        "${lt:-?}/${rt:-?}" "${lv:-?}/${rv:-?}" "${et%%.*}" "${notes[*]:-}"

    # list the actual missing files, not just the count
    [ ${#miss[@]} -gt 0 ] && printf '           missing: %s\n' "${miss[*]}"
done

log "Summary"
echo "  passed: $(( ${#SUBJECTS[@]} - ${#FAILED[@]} )) / ${#SUBJECTS[@]}"
if [ ${#FAILED[@]} -gt 0 ]; then
    bad "  failed: ${FAILED[*]}"
    echo "  inspect: freeview -v $SUBJECTS_DIR/<sid>/mri/T1.mgz \\"
    echo "             -f $SUBJECTS_DIR/<sid>/surf/lh.white:edgecolor=blue \\"
    echo "                $SUBJECTS_DIR/<sid>/surf/lh.pial:edgecolor=red"
    exit 1
fi
ok "  all requested subjects passed"
