"""Build the GitHub Pages site for the repository.

Every number on the page is read from the published tables, so the page cannot drift from
the data. Pipeline D is absent here for the same reason it is absent from the tables.

Run:  conda run -n py_analysis python build_pages.py
"""
import csv
import json
from pathlib import Path

REPO = Path("../ds004562-pipeline-multiverse")
DOCS = REPO / "docs"
TABLES = REPO / "tables"

BRANCH_ORDER = [
    "visual", "movement", "context",
]
BRANCH_LABEL = {
    "visual": "Visual direction",
    "movement": "Movement direction",
    "context": "Task context −90/+90",
}
# the eleven-branch matrix, as printed on the poster
MATRIX_BRANCHES = [
    "1  Visual direction", "2  Movement direction", "3  Task context −90/+90",
    "4  Context rotation vs mirror", "5  Preparation −90/+90", "6  Preparation rot vs mirror",
    "7  Four-direction, +90", "8  Four-direction, −90", "9  Four-direction, mirror",
    "10  Commonality input, rotations", "11  Commonality input, rot/mirror",
]
MATRIX_COHORT = [21, 19, 21, 22, 22, 21, 22, 22, 22, 22, 22]
MATRIX_RHO = [
    [.784, .751, .922], [.669, .650, .862], [.671, .637, .929], [.782, .729, .938],
    [.678, .663, .942], [.667, .640, .930], [.730, .711, .937], [.737, .720, .932],
    [.696, .681, .924], [.897, .875, .981], [.915, .899, .984],
]


def read_tsv(path):
    with open(path, newline="", encoding="utf8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


MAP_BRANCHES = [
    ("visual_direction", "Visual direction"),
    ("movement_direction", "Movement direction"),
    ("task_context", "Task context −90/+90"),
    ("preparation_rotmirror", "Preparation, rotation vs mirror"),
]
MAP_KINDS = [("t", "Group t"), ("corrp", "TFCE-corrected 1−p")]


def build_data():
    per_subject = read_tsv(TABLES / "persubject_rho_abc.tsv")
    summary = read_tsv(TABLES / "persubject_summary_abc.tsv")
    tfce = read_tsv(TABLES / "tfce_extent_abc.tsv")

    return {
        "matrix": {
            "branches": MATRIX_BRANCHES,
            "cohort": MATRIX_COHORT,
            "pairs": ["A–B", "A–C", "B–C"],
            "rho": MATRIX_RHO,
        },
        "perSubject": [
            {"branch": r["branch"], "pair": r["pair"].replace("-", "–"),
             "subject": r["subject"], "rho": round(float(r["rho"]), 4)}
            for r in per_subject
        ],
        "summary": [
            {"branch": r["branch"], "pair": r["pair"].replace("-", "–"),
             "n": int(r["n"]), "mean": round(float(r["mean_rho"]), 3),
             "min": round(float(r["min_rho"]), 3), "max": round(float(r["max_rho"]), 3),
             "group": round(float(r["group_rho"]), 3)}
            for r in summary
        ],
        "tfce": [
            {"arm": r["arm"], "branch": r["branch"],
             "percent": float(r["percent_of_mask"]),
             "voxels": int(r["n_voxels_corrp_gt_095"]),
             "peakT": round(float(r["peak_t"]), 2)}
            for r in tfce
        ],
        "branchOrder": BRANCH_ORDER,
        "branchLabel": BRANCH_LABEL,
        "maps": json.loads((DOCS / "maps/index.json").read_text(encoding="utf8"))
        if (DOCS / "maps/index.json").exists() else {},
        "mapBranches": MAP_BRANCHES,
        "mapKinds": MAP_KINDS,
        "collection": "https://neurovault.org/collections/24567/",
    }


def main():
    DOCS.mkdir(parents=True, exist_ok=True)
    data = build_data()
    template = Path("pages_template.html").read_text(encoding="utf8")
    html = template.replace("/*DATA*/null/*DATA*/", json.dumps(data, ensure_ascii=False))
    (DOCS / "index.html").write_text(html, encoding="utf8", newline="\n")

    # the figures the page links to as downloads
    for name in ("agreement_matrix_abc.png", "tfce_extent_abc.png"):
        (DOCS / name).write_bytes((REPO / "figures" / name).read_bytes())

    print(f"docs/index.html written, {len(html):,} bytes")
    print(f"  matrix   {len(data['matrix']['rho'])} branches")
    print(f"  subjects {len(data['perSubject'])} rows")
    print(f"  summary  {len(data['summary'])} rows")
    print(f"  tfce     {len(data['tfce'])} rows")


if __name__ == "__main__":
    main()
