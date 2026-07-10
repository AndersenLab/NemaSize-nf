# NemaSize-nf
Author: Zihao John Li, Apr 2026 (revised Jun 2026 for Rockfish CPU)

A Nextflow pipeline that runs [NemaSize](https://github.com/AndersenLab/NemaSize)
on *C. elegans* images by scattering hundreds of small CPU jobs across the
Rockfish `parallel` partition. Replaces the old "submit one big GPU job to
DSAI" flow — for typical datasets the parallelized CPU run finishes in less
wall time and uses no GPU quota.

> The previous DSAI-via-ssh design is preserved in
> [main_dsai_legacy.nf](main_dsai_legacy.nf) and documented in
> [README_dsai_legacy.md](README_dsai_legacy.md). See
> [Running the legacy DSAI pipeline](#running-the-legacy-dsai-pipeline) below.

## Overview

```
<data_f>/raw_images/*.{tif,png,jpg,...}
        │
        ▼
┌──────────────────────┐
│ DISCOVER_IMAGES      │   list every raw image → all_images.txt
└──────────┬───────────┘
           │ splitText (20 / batch by default)
           ▼
┌──────────────────────┐
│ MAKE_BATCH_DIR (×N)  │   <data_f>/batches/batch_<i>/batch_<i>.txt
└──────────┬───────────┘
           │  ── barrier (collect → flatMap) ──
           ▼
┌──────────────────────┐
│ RUN_BATCH (×N, SLURM)│   singularity NemaSize on each batch
└──────────┬───────────┘
           │  ── barrier (collect) ──
           ▼
┌──────────────────────┐
│ MERGE_RESULTS (SLURM)│   <data_f>/NemaSize_output/
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ CLEANUP_BATCHES      │   rm -rf <data_f>/batches/
└──────────────────────┘
```

The two `collect` barriers guarantee:
- `RUN_BATCH` only starts after every batch directory exists, and
- `MERGE_RESULTS` only runs after every `RUN_BATCH` succeeded (any failure
  aborts the run before merge / cleanup).

## Requirements

- [Nextflow](https://www.nextflow.io/) ≥ 22.x (lab conda env `nf24_env` is fine)
- Access to the Rockfish `parallel` partition (most users have this)
- A shared Singularity image cache. The lab convention is
  `/vast/eande106/singularity/`; the NemaSize CPU image is pre-staged at
  `/vast/eande106/singularity/zihaojohnli-nemasize-1.0.0-cpu.img`.
- Your data folder must contain a `raw_images/` subfolder of `.tif/.tiff/.png/.jpg/.jpeg`.

## Quick start

From your home directory (avoids NFS file-lock issues on `/vast`):

```bash
module load anaconda
source activate /data/eande106/software/conda_envs/nf24_env

# tell Nextflow where the shared singularity cache lives
export NXF_SINGULARITY_CACHEDIR=/vast/eande106/singularity

cd ~
nextflow run andersenlab/nemasize-nf \
  --data_f /path/to/your/data_folder \
  -w /path/to/your/work_dir
```

That's it — no `-profile rockfish` needed (the default profile already maps
to the Rockfish config).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--data_f` | Absolute path to the data folder (must contain `raw_images/`) | **required** |
| `--batch_size` | Images per RUN_BATCH job. **Hard-capped at 25** (1h SLURM wall time) | `20` |
| `--clean_batches` | Wipe `<data_f>/batches/` *before* the run starts (keeps resumes idempotent) | `true` |
| `--clean_intermediate` | Delete `<data_f>/batches/` *after* a successful merge | `true` |
| `--force_merge` | Overwrite an existing `<data_f>/NemaSize_output/` instead of failing | `false` |

Standard Nextflow flags also work: `-resume`, `-w <work_dir>`, `-profile rockfish`,
`-N your@email.com` for completion email, etc.

### Why `batch_size ≤ 25`?

`RUN_BATCH` requests 1 hour of SLURM wall time per job. Empirically, 20
images per batch can take up to ~35 minutes on the `parallel` partition
(~1.75 min/image worst case). 25 is therefore the safe upper bound:
worst-case ≈ 44 minutes, leaving ~16 minutes of headroom inside the 1h
limit. Anything larger risks per-job timeouts and is rejected up front.

If you genuinely need bigger batches, raise **both**:

1. the cap check in [main.nf](main.nf) (the `params.batch_size > 25` line), and
2. the `time =` directive under `withName: RUN_BATCH` in
   [conf/rockfish.config](conf/rockfish.config).

## Example

```bash
cd ~
nextflow run andersenlab/nemasize-nf \
  --data_f /vast/eande106/projects/John/NemaSeg/Datasets/John/Parallel_test \
  --batch_size 20 \
  -w /vast/eande106/projects/John/work/nemasize-nf
```

For 103 images at `--batch_size 20` this produces 6 SLURM jobs
(20+20+20+20+20+3) running in parallel on the `parallel` partition.

## Output layout

After a successful run:

```
<data_f>/
├── raw_images/                          (your input, unchanged)
└── NemaSize_output/
    ├── roi_catalog.json                 (ROI metadata, merged from all batches)
    └── skeleton/
        ├── worm_sizes.csv               (single header, all rows concatenated)
        └── contour_skeleton_txt/        (per-ROI contour+skeleton .txt files)
```

Set `--clean_intermediate false` if you want to keep `<data_f>/batches/`
around for debugging (each `batches/batch_<i>/` holds that batch's
unmerged `NemaSize_output/`).

## Resuming and re-running

- **Resume:** `nextflow run … -resume` — skips any task whose inputs are
  unchanged. Useful after a transient SLURM failure.
- **Re-run merge only:** delete `<data_f>/NemaSize_output/` (or pass
  `--force_merge`) and `-resume`. RUN_BATCH stays cached; only MERGE_RESULTS
  re-executes.
- **Full restart:** delete the Nextflow `work/` directory and `<data_f>/batches/`.

## Pipeline reports

Saved to `pipeline_info/` (relative to your launch dir):

- `*_timeline.html` — task timeline
- `*_report.html` — resource usage
- `*_trace.txt` — per-task execution trace
- `*_dag.svg` — workflow DAG

## SLURM resources

Configured in [`conf/rockfish.config`](conf/rockfish.config):

| Process | Executor | Queue | CPUs | Memory | Time |
|---|---|---|---|---|---|
| `DISCOVER_IMAGES` | local | — | — | — | — |
| `MAKE_BATCH_DIR`  | local | — | — | — | — |
| `RUN_BATCH`       | slurm | `parallel` | 4 | 16 GB | 1 h |
| `MERGE_RESULTS`   | slurm | `parallel` | 1 | 8 GB  | 30 min |
| `CLEANUP_BATCHES` | local | — | — | — | — |

`executor.queueSize = 250` caps concurrent SLURM submissions to keep both
SLURM and the login-node Nextflow process responsive.

## Running the legacy DSAI pipeline

The original pipeline — which submits a single large GPU job to the DSAI
cluster over `ssh`/`scp` — is preserved as
[main_dsai_legacy.nf](main_dsai_legacy.nf) and is unaffected by the Rockfish
rewrite. Use it when you specifically want the old DSAI GPU flow (e.g.
running on a DSAI-only dataset or comparing results).

### Requirements (legacy)

- SSH key-based access to `dsailogin.arch.jhu.edu` via `~/.ssh/id_rsaNemaSize`
- The SLURM template at [assets/NemaSize_slurm_temp.sh](assets/NemaSize_slurm_temp.sh)
  (still shipped with the repo)
- Data folder containing a `raw_images/` subfolder

### Usage (legacy)

```bash
module load python/anaconda
source activate /data/eande106/software/conda_envs/nf24_env

cd ~
nextflow run /vast/eande106/projects/John/Repo/NemaSize-nf/main_dsai_legacy.nf \
  --data_f /path/to/your/data_folder \
  --email your@email.com \
  -w /vast/eande106/projects/John/Repo/NemaSize-nf/work
```

### Legacy parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--data_f` | Absolute path to the data folder (must contain `raw_images/`) | **required** |
| `--email` | Email for SLURM job notifications on the DSAI side | **required** |
| `--slurm_temp` | SLURM script template | `assets/NemaSize_slurm_temp.sh` |

### Retrieving results (legacy)

After the DSAI SLURM job finishes, run the auto-generated transfer script:

```bash
bash /path/to/your/data_folder/transfer_results.sh
```

It pulls `NemaSize_output/` back from DSAI and removes the project folder
on the DSAI cluster. See [README_dsai_legacy.md](README_dsai_legacy.md) for
the full details and SLURM resource defaults.

> **Note:** the new Rockfish flow and the legacy DSAI flow share
> [nextflow.config](nextflow.config). Singularity is enabled globally, but
> none of the legacy processes set a `container` directive, so it has no
> effect on them — you can run either pipeline against the same config
> without changes.
