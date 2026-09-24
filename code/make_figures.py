"""Poster figures that need no server data. Numbers come from the verified 2026-09-16 record
and the round-5/6 in-memory runs."""
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Patch

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 11, "axes.spines.top": False,
    "axes.spines.right": False, "figure.dpi": 300, "savefig.dpi": 300,
    "savefig.bbox": "tight", "axes.titlesize": 13, "axes.titleweight": "bold",
})
NAVY, BLUE, AMBER, GREY, RED = "#1B4477", "#2C5F9E", "#B47A1E", "#9CA3AF", "#C0392B"
OUT = "figures/"
M = "−"

PAIRS_ABC = ["A–B", "A–C", "B–C"]
PAIRS_D = ["A–D", "B–D", "C–D"]
PAIRS = PAIRS_ABC + PAIRS_D

BRANCHES = [
    "1  Visual direction (Fig 6)",
    "2  Movement direction (Fig 7)",
    "3  Context " + M + "90/+90, erasing (Fig 8)",
    "4  Context rotation vs mirror †",
    "5  Preparation " + M + "90/+90 †",
    "6  Preparation rot vs mirror (Fig 9)",
    "7  Four-direction, +90",
    "8  Four-direction, " + M + "90",
    "9  Four-direction, mirror",
    "10  Commonality input, rotations †",
    "11  Commonality input, rot/mirror †",
]
N = np.nan
RHO = np.array([
    [.784, .751, .922, .503, .457, .440],
    [.669, .650, .862, -.225, -.180, -.191],
    [.671, .637, .929, .095, .114, .107],
    [.782, .729, .938, N, N, N],
    [.678, .663, .942, N, N, N],
    [.667, .640, .930, N, N, N],
    [.730, .711, .937, N, N, N],
    [.737, .720, .932, N, N, N],
    [.696, .681, .924, N, N, N],
    [.897, .875, .981, N, N, N],
    [.915, .899, .984, N, N, N],
])
CARE_ABC_ROWS = {4, 9, 10}      # branches 5, 10, 11 in the A/B/C figure
COHORT = ["21", "19", "21", "22", "22", "21", "22", "22", "22", "22", "22"]


def draw_cells(ax, values, care, fmt_color=True):
    for i in range(values.shape[0]):
        for j in range(values.shape[1]):
            v = values[i, j]
            if np.isnan(v):
                ax.add_patch(plt.Rectangle((j - .5, i - .5), 1, 1, facecolor="#F1F2F4",
                                           edgecolor="white", hatch="///", lw=1.5))
                ax.text(j, i, "no map", ha="center", va="center", color=GREY, fontsize=8.5)
                continue
            txt = f"{v:.3f}".replace("0.", ".").replace("-", M)
            ax.text(j, i, txt, ha="center", va="center", fontsize=11, fontweight="bold",
                    color="white" if (fmt_color and abs(v) > .55) else "#24272E")
            if care[i, j]:
                ax.add_patch(plt.Rectangle((j - .5, i - .5), 1, 1, fill=False,
                                           edgecolor=AMBER, lw=2.8))


def grid(ax, nrow, ncol, xlabels, ylabels, xsize=12, ysize=10.5, yleft=False):
    ax.set_xticks(range(ncol), xlabels, fontsize=xsize, fontweight="bold")
    ax.set_yticks(range(nrow), ylabels, fontsize=ysize)
    if yleft:
        # flush the branch names to a common left edge instead of ragged-left
        fig = ax.figure
        fig.canvas.draw()
        r = fig.canvas.get_renderer()
        widest = max(t.get_window_extent(r).width for t in ax.get_yticklabels())
        for t in ax.get_yticklabels():
            t.set_horizontalalignment("left")
        ax.tick_params(axis="y", pad=widest * 72 / fig.dpi + 6)
    ax.set_xticks(np.arange(-.5, ncol, 1), minor=True)
    ax.set_yticks(np.arange(-.5, nrow, 1), minor=True)
    ax.grid(which="minor", color="white", lw=2)
    ax.tick_params(which="minor", length=0)
    ax.tick_params(length=0)


# ---------------------------------------------------------------- TFCE (2026-09-22 runs)
TFCE_PCT = {           # percent of the 158,156-voxel mask with corrected p < .05
    "Visual (Fig 6)": [7.726, 5.907, 6.491, 22.018],
    "Movement (Fig 7)": [44.387, 46.299, 43.881, 11.344],
    "Context ±90 (Fig 8)": [25.364, 0.594, 0.273, 99.999],
}
TFCE_ALL4 = {          # voxels significant in all four pipelines
    "Visual (Fig 6)": 9019,
    "Movement (Fig 7)": 928,
    "Context ±90 (Fig 8)": 292,
}
MASK_N = 158156


def fig_tfce():
    fig, axes = plt.subplots(1, 2, figsize=(11.5, 3.6),
                             gridspec_kw={"width_ratios": [2.1, 1]})
    colors = [NAVY, BLUE, "#7FA6D4", AMBER]
    ax = axes[0]
    x = np.arange(3)
    w = .2
    for k, arm in enumerate(["A", "B", "C", "D"]):
        vals = [TFCE_PCT[b][k] for b in TFCE_PCT]
        ax.bar(x + (k - 1.5) * w, vals, w * .9, color=colors[k], label=f"Pipeline {arm}")
    ax.set_yscale("log")
    ax.set_ylim(.1, 400)
    ax.set_xticks(x, list(TFCE_PCT), fontsize=11)
    ax.set_ylabel("% of mask, corrected p < .05")
    ax.set_title("Significant extent after TFCE (5,000 permutations)")
    ax.legend(frameon=False, fontsize=10, ncol=4, loc="upper center",
              bbox_to_anchor=(.5, -.14))
    ax.annotate("99.999%", xy=(2 + 1.5 * w, 99.999), xytext=(1.30, 230), color=RED,
                fontsize=9.5, arrowprops=dict(arrowstyle="->", color=RED, lw=1.3))
    ax.annotate(".59% / .27%", xy=(2 - .5 * w, .594), xytext=(1.42, .145), color=RED,
                fontsize=9.5, arrowprops=dict(arrowstyle="->", color=RED, lw=1.3))

    ax = axes[1]
    pct = [100 * TFCE_ALL4[b] / MASK_N for b in TFCE_ALL4]
    ax.bar(np.arange(3), pct, .55, color=NAVY)
    for i, (b, v) in enumerate(zip(TFCE_ALL4, pct)):
        ax.text(i, v + .12, f"{TFCE_ALL4[b]:,}", ha="center", fontsize=9.5)
    ax.set_xticks(np.arange(3), ["Visual", "Movement", "Context"], fontsize=11)
    ax.set_ylabel("% of mask")
    ax.set_ylim(0, 7)
    ax.set_title("Significant in all four pipelines")
    fig.suptitle("Where a threshold is applied, the pipelines diverge far more than their unthresholded maps do",
                 fontsize=13, fontweight="bold", y=1.04)
    fig.savefig(OUT + "fig_tfce.png")
    plt.close(fig)


def fig_matrix_abc():
    """All 11 branches, the three pipelines that share Song's decoding design."""
    vals = RHO[:, :3]
    care = np.zeros_like(vals, dtype=bool)
    for r in CARE_ABC_ROWS:
        care[r, :] = True
    fig, ax = plt.subplots(figsize=(6.6, 7.2))
    im = ax.imshow(vals, cmap="RdBu", vmin=-1, vmax=1, aspect="auto")
    draw_cells(ax, vals, care)
    labels = [f"{b}   (n = {c})" for b, c in zip(BRANCHES, COHORT)]
    grid(ax, 11, 3, PAIRS_ABC, labels, yleft=True)
    ax.set_title("Pipelines A, B and C: agreement across all 11 branches", pad=14)
    cb = fig.colorbar(im, ax=ax, shrink=.5, pad=.03)
    cb.set_label("Spearman " + r"$\rho$")
    ax.legend(handles=[Patch(facecolor="white", edgecolor=AMBER, lw=2.8,
                             label="interpret with care (see †)")],
              loc="upper center", bbox_to_anchor=(.5, -.06), frameon=False, fontsize=10)
    fig.savefig(OUT + "fig_matrix_abc.png")
    plt.close(fig)


def fig_matrix_four_arms():
    """The three branches for which pipeline D also has a map."""
    vals = RHO[:3, :]
    care = np.zeros_like(vals, dtype=bool)
    care[:, 3:] = True
    fig, ax = plt.subplots(figsize=(9.2, 3.4))
    im = ax.imshow(vals, cmap="RdBu", vmin=-1, vmax=1, aspect="auto")
    draw_cells(ax, vals, care)
    labels = [f"{b}   (n = {c})" for b, c in zip(BRANCHES[:3], COHORT[:3])]
    grid(ax, 3, 6, PAIRS, labels, yleft=True)
    ax.set_title("All four pipelines: the three branches pipeline D also has", pad=12)
    cb = fig.colorbar(im, ax=ax, shrink=.85, pad=.02)
    cb.set_label("Spearman " + r"$\rho$")
    ax.legend(handles=[Patch(facecolor="white", edgecolor=AMBER, lw=2.8,
                             label="Pipeline D: different cross-validation, interpret with care")],
              loc="upper center", bbox_to_anchor=(.5, -.18), frameon=False, fontsize=10)
    fig.savefig(OUT + "fig_matrix_four_arms.png")
    plt.close(fig)


GROUP = {"Visual (Fig 6)": [.784, .751, .922, .503, .457, .440],
         "Movement (Fig 7)": [.669, .650, .862, -.225, -.180, -.191],
         "Context ±90 (Fig 8)": [.671, .637, .929, .095, .114, .107]}
SUBJ = {"Visual (Fig 6)": ([.634, .597, .874, .302, .283, .282], [.109, .111, .055, .104, .108, .098]),
        "Movement (Fig 7)": ([.606, .569, .870, -.107, -.078, -.082], [.085, .073, .061, .078, .058, .054]),
        "Context ±90 (Fig 8)": ([.587, .565, .919, .028, .018, .018], [.084, .072, .021, .110, .122, .127])}


def fig_group_vs_subject():
    fig, axes = plt.subplots(1, 3, figsize=(13.5, 3.6), sharey=True)
    x = np.arange(6)
    for ax, (name, g) in zip(axes, GROUP.items()):
        m, sd = SUBJ[name]
        ax.axhline(0, color="#C9CDD4", lw=1)
        ax.bar(x - .2, g, .38, color=NAVY, label="group maps")
        ax.bar(x + .2, m, .38, yerr=sd, color=BLUE, alpha=.55, capsize=3,
               error_kw=dict(lw=1, ecolor="#6B7280"), label="per subject (mean ± SD)")
        ax.set_xticks(x, PAIRS, fontsize=11)
        ax.set_title(name)
        ax.set_ylim(-.45, 1.0)
    axes[0].set_ylabel("Spearman " + r"$\rho$")
    axes[0].legend(frameon=False, fontsize=10, loc="upper left")
    fig.suptitle("Group-level agreement is systematically higher than within-subject agreement",
                 fontsize=13, fontweight="bold", y=1.03)
    fig.savefig(OUT + "fig_group_vs_subject.png")
    plt.close(fig)


DIAG = {"Visual (Fig 6)": ([.634, .597, .874, .302, .283, .282], [.142, .142, .130, .171, .153, .152]),
        "Movement (Fig 7)": ([.606, .569, .870, -.107, -.078, -.082], [.052, .053, .040, -.078, -.065, -.066]),
        "Context ±90 (Fig 8)": ([.587, .565, .919, .028, .018, .018], [.010, .009, .003, .018, .014, .013])}
LEVEL = {"Visual (Fig 6)": [.34, -.01, .04, 1.13],
         "Movement (Fig 7)": [1.09, 1.15, 1.08, .38],
         "Context ±90 (Fig 8)": [2.68, 1.86, 1.57, 24.21]}


def fig_armd():
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 3.4))
    colors = [NAVY, BLUE, "#7FA6D4"]
    w = .26
    ax = axes[0]
    x = np.arange(6)
    for k, (name, (dia, off)) in enumerate(DIAG.items()):
        diff = np.array(dia) - np.array(off)
        pos = x + (k - 1) * w
        ax.bar(pos, diff, w * .9, color=colors[k], label=name)
        if k > 0:
            for j in (3, 4, 5):
                ax.text(pos[j], max(diff[j], 0) + .03, "n.s.", ha="center", va="bottom",
                        fontsize=8, color=RED, rotation=90)
    ax.axhline(0, color="#C9CDD4", lw=1)
    ax.set_xticks(x, PAIRS, fontsize=11)
    ax.set_ylabel(r"$\rho$ same subject $-$ $\rho$ different subjects")
    ax.set_title("Is the agreement subject-specific?")
    ax.legend(frameon=False, fontsize=9.5, loc="upper right")
    ax.set_ylim(-.12, 1.02)

    ax = axes[1]
    x = np.arange(4)
    for k, (name, lv) in enumerate(LEVEL.items()):
        ax.bar(x + (k - 1) * w, lv, w * .9, color=colors[k], label=name)
    ax.axhline(0, color="#C9CDD4", lw=1)
    ax.set_xticks(x, ["Pipeline A", "Pipeline B", "Pipeline C", "Pipeline D"], fontsize=11)
    ax.set_ylabel("mean accuracy " + M + " chance (pp)")
    ax.set_title("Decoding level inside the mask")
    ax.set_ylim(0, 29)
    ax.annotate("24.2 pp — block identity\nstays in the training set", xy=(3 + w, 24.5),
                xytext=(1.0, 20.5), fontsize=9.5, color=RED,
                arrowprops=dict(arrowstyle="->", color=RED, lw=1.4))
    ax.legend(frameon=False, fontsize=9.5, loc="upper left")
    fig.suptitle("Pipeline D keeps a subject-specific pattern for visual direction, but not for movement or context",
                 fontsize=13, fontweight="bold", y=1.04)
    fig.savefig(OUT + "fig_armd.png")
    plt.close(fig)


fig_matrix_abc()
fig_matrix_four_arms()
fig_group_vs_subject()
fig_armd()
fig_tfce()
print("figures written")
