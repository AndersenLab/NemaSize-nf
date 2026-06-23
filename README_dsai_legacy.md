# NemaSize-nf
Author: Zihao John Li, Apr 2026

A Nextflow pipeline for submitting NemaSize jobs to the DSAI cluster from the Rockfish cluster.

## Overview

This pipeline automates the following steps:

1. **Generate a SLURM script** — fills in job-specific fields (job name, output path, data folder, email) from a template.
2. **Transfer data** — copies the `raw_images` subfolder and the generated SLURM script to the DSAI cluster via `scp`.
3. **Submit the job** — creates a `NemaSize_output` directory on the DSAI cluster and submits the SLURM script via `ssh`.
4. **Generate a transfer-back script** — creates `transfer_results.sh` inside your data folder for retrieving results after the job completes.

## Requirements

- [Nextflow](https://www.nextflow.io/) ≥ 22.x
- SSH key-based access to `dsailogin.arch.jhu.edu` (via `~/.ssh/id_rsaNemaSize`)
- Data folder containing a `raw_images` subfolder

## Usage

Run the pipeline from your **home directory** (to avoid NFS file lock issues on `/vast`).

First, make sure the Nextflow environment is loaded:

```bash
module load python/anaconda
source activate /data/eande106/software/conda_envs/nf24_env
```

Then run:

```bash
cd ~
nextflow run /path/to/NemaSize-nf/main.nf \
  --data_f /path/to/your/data_folder \
  --email your@email.com \
  -w /path/to/NemaSize-nf/work
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--data_f` | Absolute path to the local data folder (must contain `raw_images/`) | Required |
| `--email` | Email address for SLURM job notifications | Required |
| `--slurm_temp` | Path to the SLURM script template | `assets/NemaSize_slurm_temp.sh` |

### Example

```bash
cd ~
nextflow run /vast/eande106/projects/John/Repo/NemaSize-nf/main.nf \
  --data_f /vast/eande106/projects/John/NemaSeg/Datasets/John/Nextflow_test \
  --email zli435@jh.edu \
  -w /vast/eande106/projects/John/Repo/NemaSize-nf/work
```

## Transferring Results Back

After the SLURM job finishes, run the generated script to pull results back to your data folder:

```bash
bash /path/to/your/data_folder/transfer_results.sh
```

This script will:
1. Remove any stale local `NemaSize_output` folder
2. Transfer `NemaSize_output` from the DSAI cluster to your data folder
3. Delete the project folder on the DSAI cluster

The script uses `set -e`, so if any step fails it stops immediately to prevent data loss.

## SLURM Job Configuration

The SLURM template (`assets/NemaSize_slurm_temp.sh`) is configured for the DSAI cluster with the following defaults:

| Resource | Value |
|----------|-------|
| Partition | `a100` |
| CPUs | 1 |
| Memory | 128 GB |
| GPU | 1 |
| Wall time | 24 hours |
| Conda environment | `/scratch/eande106/conda_envs/nemaseg` |

Edit the template to adjust resource settings as needed.

## Output

Pipeline execution reports are saved to `pipeline_info/`:

- `*_timeline.html` — task timeline
- `*_report.html` — resource usage report
- `*_trace.txt` — execution trace
- `*_dag.svg` — workflow DAG

SLURM job output (`.out` / `.err`) is written to `/scratch/eande106/NemaSize/<data_folder>/NemaSize_output/` on the DSAI cluster.