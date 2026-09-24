# Code

How the tables, figures and pages in this repository were produced. These scripts ran in a
working directory that also held the results fetched from the analysis machine, so their
relative paths (`from_server/`, `../ds004562-pipeline-multiverse`) describe that layout. They
are published as a record of how each artefact was made, not as a turnkey pipeline.

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

**The analysis itself.** The preprocessing, first-level models, searchlight decoding and the
permutation tests ran on a laboratory server against the raw dataset; that code is not in this
repository. What is here starts from the finished maps.

**The fetch script.** It carries the server's address and directory layout, so it stays
private.

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
