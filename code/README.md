# Code

Two layers. `analysis/` is the analysis itself, as it ran on the laboratory server. The files
beside it turn the finished maps into the tables, figures and pages in this repository.

Neither layer is a turnkey pipeline: absolute paths have been replaced by placeholders such as
`<DATA_ROOT>`, and the scripts assume the directory layout they ran in. They are published so
that what was done can be read, checked and adapted.

## `analysis/` - the pipelines

139 files, organised as `pipeline-a/`, `pipeline-b/`, `pipeline-c/` and `shared/`, with
`MANIFEST.md` giving the execution order, inputs and outputs for each pipeline, and
`SANITIZATION.md` accounting for every replacement made before publication.

- **Pipeline A** SPM12 / CONN / ART preprocessing, SPM first-level models, searchlight decoding
  in The Decoding Toolbox, then FSL randomise at the group level.
- **Pipeline B** the same analysis on fMRIPrep preprocessing. `shared/preprocessing/` holds the
  fMRIPrep and FastSurfer launchers and a record of the two cohort runs, including the expanded
  container commands.
- **Pipeline C** the same preprocessing, reimplemented downstream in Nilearn and scikit-learn.
- **`group-randomise/`** under each pipeline holds, per branch, the exact `randomise` command
  with its design matrix and contrast file, byte-identical to what was executed.

### Software as executed

| | |
| --- | --- |
| Operating system | Ubuntu 24.04.5 LTS |
| MATLAB | R2025b (25.2) |
| SPM | SPM12 r7771 |
| CONN | 25.b (ART bundled, release 7/19/11) |
| The Decoding Toolbox | 3.999I, with LIBSVM 3.17 |
| fMRIPrep | 25.2.5 (Nipype 1.10.0, TemplateFlow 25.0.4) |
| FastSurfer | 2.5.4 (`deepmi/fastsurfer:cu128-v2.5.4`) |
| ANTs | 2.6.4.post1-gdfadbfe |
| Python | 3.12.13 - NumPy 2.5.1, SciPy 1.18.0, pandas 3.0.5, nibabel 5.4.2, Nilearn 0.14.0, scikit-learn 1.8.0, h5py 3.16.0 |
| FSL | 6.0.7.23 (randomise) |

### Known gaps

**Group-level tests are preserved for some branches, not all.** The `randomise` command,
design and contrast survive for pipeline A branches 1, 2, 3, 5 and 6 plus two regressions, and
for pipelines B and C branches 1, 2, 3 and 6. For the remaining branch cells no invocation or
output was found. Whether those tests were never run, or were run and not preserved, cannot be
determined from what remains, and we do not claim either.

This does not affect the agreement figures in this repository: every rho is computed from the
accuracy maps and does not depend on the group-level tests. The significant-extent results use
only branches for which the tests are preserved.

**The interactive shell transcript of the preprocessing runs was not kept.** The launcher
scripts and the cohort logs are the record; `shared/preprocessing/cohort_runs_20260924.md`
reconstructs the commands from them.

## The rest - from maps to artefacts

These ran in a working directory that also held the results fetched from the server, so their
relative paths (`from_server/`, `../ds004562-pipeline-multiverse`) describe that layout.

| File | What it does |
| --- | --- |
| `build_repo.py` | Filters the result tables to pipelines A, B and C and draws the significant-extent chart. Every table in `../tables` comes from here. |
| `build_pages.py` + `pages_template.html` | Builds `docs/index.html`. Every number on that page is read from the published tables at build time, so the page cannot drift from the data. |
| `make_figures.py` | Draws the agreement matrices and the threshold chart used on the poster. |
| `figure_blocks.py` | Splits the rendered brain figures into their t-map and accuracy blocks by finding the blank gutter between them, rather than cutting at a fixed fraction. |
| `neurovault_upload.py` | Uploads the group maps to [NeuroVault](https://neurovault.org/collections/24567/), one image per pipeline, branch and map type. |
| `test_crop_blocks.py` | Checks the block split lands in the gutter and loses no rows of brain. |
| `test_neurovault_upload.py` | Checks each map is described correctly, and that the partner laboratory's pipeline is not uploaded unless explicitly asked for. |

## What is not here

**The fetch script.** It carries the server's address and directory layout, so it stays
private.

**The data.** Only code. The dataset is OpenNeuro ds004562; the group maps are on NeuroVault.

**The partner laboratory's pipeline.** Its maps and the agreement numbers involving them are
withheld until they agree to publication, and `neurovault_upload.py` will not upload them
without an explicit flag.

## Running them

Python 3.12 with `numpy`, `matplotlib`, `pillow`, `requests` and `segno`. The tests need
`opencv-python-headless` as well. Each script is run directly:

```bash
python build_repo.py
python build_pages.py
python test_crop_blocks.py
```
