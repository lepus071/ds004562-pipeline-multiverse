"""Assemble the public repository the poster's QR code points to.

Pipeline D is the partner lab's analysis and is withheld until they agree to publication,
so every table is filtered to the A, B and C rows and every figure is redrawn without D.
`test_repo_has_no_pipeline_d.py` checks that nothing slipped through.

Run:  conda run -n py_analysis python build_repo.py
"""
import csv
import shutil
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

SRC = Path("from_server")
FIG = Path("figures")
REPO = Path("../ds004562-pipeline-multiverse")

KEEP_PAIRS = {"A-B", "A-C", "B-C"}
KEEP_ARMS = {"A", "B", "C"}

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 11, "axes.spines.top": False,
    "axes.spines.right": False, "figure.dpi": 200, "savefig.dpi": 200,
    "savefig.bbox": "tight", "axes.titlesize": 13, "axes.titleweight": "bold",
})
NAVY, BLUE, PALE = "#1B4477", "#2C5F9E", "#8FB4DC"


def filter_tsv(src, dst, column, keep, drop_columns=()):
    with open(src, newline="", encoding="utf8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    fields = [c for c in rows[0] if c not in drop_columns]
    kept = [r for r in rows if r[column] in keep]
    dst.parent.mkdir(parents=True, exist_ok=True)
    with open(dst, "w", newline="", encoding="utf8") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        w.writerows(kept)
    return len(rows), len(kept)


def tfce_chart(summary_tsv, dst):
    """Significant extent per branch for A, B and C only."""
    with open(summary_tsv, newline="", encoding="utf8") as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t") if r["arm"] in KEEP_ARMS]
    branches = sorted({r["branch"] for r in rows})
    fig, ax = plt.subplots(figsize=(7.2, 3.6))
    width = 0.26
    x = np.arange(len(branches))
    for k, (arm, colour) in enumerate(zip("ABC", (NAVY, BLUE, PALE))):
        vals = [float(next(r["percent_of_mask"] for r in rows
                           if r["arm"] == arm and r["branch"] == b)) for b in branches]
        bars = ax.bar(x + (k - 1) * width, vals, width * .9, color=colour, label=f"Pipeline {arm}")
        ax.bar_label(bars, fmt="%.2f", fontsize=8, padding=2)
    ax.set_yscale("log")
    top = max(float(r["percent_of_mask"]) for r in rows)
    ax.set_ylim(top=top * 8)          # headroom so no bar label hides under the legend
    ax.set_xticks(x, [b.replace(" ", "\n", 1) for b in branches], fontsize=10)
    ax.set_ylabel("% of mask, corrected p < .05")
    ax.set_title("Significant extent after TFCE (5,000 permutations)")
    ax.legend(frameon=False, ncol=3, fontsize=10)
    fig.savefig(dst)
    plt.close(fig)
    return branches


def main():
    REPO.mkdir(parents=True, exist_ok=True)
    (REPO / "figures").mkdir(exist_ok=True)
    (REPO / "tables").mkdir(exist_ok=True)

    n1, k1 = filter_tsv(SRC / "persubject_rho_20260922.tsv",
                        REPO / "tables/persubject_rho_abc.tsv", "pair", KEEP_PAIRS)
    n2, k2 = filter_tsv(SRC / "persubject_summary_20260922.tsv",
                        REPO / "tables/persubject_summary_abc.tsv", "pair", KEEP_PAIRS)
    # output_dir holds server paths that have no business in a public repository
    n3, k3 = filter_tsv(SRC / "summary_frozenmask_20260922.tsv",
                        REPO / "tables/tfce_extent_abc.tsv", "arm", KEEP_ARMS,
                        drop_columns=("output_dir",))

    shutil.copy2(FIG / "fig_matrix_abc.png", REPO / "figures/agreement_matrix_abc.png")
    branches = tfce_chart(SRC / "summary_frozenmask_20260922.tsv",
                          REPO / "figures/tfce_extent_abc.png")

    print(f"per-subject rho   {k1}/{n1} rows kept")
    print(f"per-subject means {k2}/{n2} rows kept")
    print(f"tfce extent       {k3}/{n3} rows kept, branches: {', '.join(branches)}")
    print(f"repository assembled at {REPO.resolve()}")


if __name__ == "__main__":
    main()
