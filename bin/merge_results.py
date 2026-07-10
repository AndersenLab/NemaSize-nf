#!/usr/bin/env python3
"""
Merge per-batch NemaSize outputs into a single <data_f>/NemaSize_output/ tree.

Inputs (per batch dir):
    batch_<i>/inference_rois/roi_catalog.json
    batch_<i>/NemaSize_output/skeleton/worm_sizes.csv
    batch_<i>/NemaSize_output/skeleton/contour_skeleton_txt/*.txt

Output (single, mirrors the original DSAI layout):
    <data_f>/NemaSize_output/
        roi_catalog.json
        skeleton/
            worm_sizes.csv
            contour_skeleton_txt/*.txt

Fails if <data_f>/NemaSize_output/ already exists, unless --force is given.
ROI stems are globally unique (image stem + roi index), so concat/move/dict-update
are safe across batches.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path


def merge(batch_dirs: list[Path], out_root: Path, force: bool) -> None:
    if out_root.exists():
        if not force:
            sys.exit(
                f"ERROR: {out_root} already exists. Re-run with --force to overwrite."
            )
        shutil.rmtree(out_root)

    skel_out = out_root / "skeleton"
    txt_out  = skel_out / "contour_skeleton_txt"
    txt_out.mkdir(parents=True, exist_ok=True)

    catalog: dict = {}
    csv_path = skel_out / "worm_sizes.csv"
    csv_header_written = False

    n_csv_rows = 0
    n_txt_files = 0

    with csv_path.open("w", encoding="utf-8", newline="") as csv_out:
        for bdir in batch_dirs:
            # ---- roi_catalog.json ----
            cat_in = bdir / "inference_rois" / "roi_catalog.json"
            if cat_in.is_file():
                with cat_in.open("r", encoding="utf-8") as f:
                    part = json.load(f)
                # Keys are unique across batches by construction (image stem +
                # roi index); guard anyway so duplicates would be visible.
                overlap = catalog.keys() & part.keys()
                if overlap:
                    sys.exit(
                        f"ERROR: duplicate ROI keys between batches "
                        f"(first overlap: {next(iter(overlap))})"
                    )
                catalog.update(part)
            else:
                print(f"WARN: missing {cat_in}", file=sys.stderr)

            # ---- worm_sizes.csv ----
            csv_in = bdir / "NemaSize_output" / "skeleton" / "worm_sizes.csv"
            if csv_in.is_file():
                with csv_in.open("r", encoding="utf-8") as f:
                    header = f.readline()
                    if not csv_header_written:
                        csv_out.write(header)
                        csv_header_written = True
                    for line in f:
                        csv_out.write(line)
                        if line.strip():
                            n_csv_rows += 1
            else:
                print(f"WARN: missing {csv_in}", file=sys.stderr)

            # ---- contour_skeleton_txt/ ----
            txt_in_dir = bdir / "NemaSize_output" / "skeleton" / "contour_skeleton_txt"
            if txt_in_dir.is_dir():
                for txt in txt_in_dir.iterdir():
                    if txt.is_file() and txt.suffix == ".txt":
                        dst = txt_out / txt.name
                        if dst.exists():
                            sys.exit(
                                f"ERROR: duplicate contour/skeleton file: {txt.name}"
                            )
                        shutil.copy2(txt, dst)
                        n_txt_files += 1
            else:
                print(f"WARN: missing {txt_in_dir}", file=sys.stderr)

    with (out_root / "roi_catalog.json").open("w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2)

    print(
        f"MERGE_RESULTS: {len(batch_dirs)} batch(es) -> {out_root}\n"
        f"  catalog entries : {len(catalog)}\n"
        f"  CSV data rows   : {n_csv_rows}\n"
        f"  contour txt     : {n_txt_files}"
    )


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-root", required=True,
                   help="Destination dir; <data_f>/NemaSize_output/")
    p.add_argument("--force", action="store_true",
                   help="Overwrite <out-root> if it exists.")
    p.add_argument("batch_dirs", nargs="+",
                   help="One or more batch_<i>/ directories.")
    args = p.parse_args()

    bdirs = [Path(b) for b in args.batch_dirs]
    for b in bdirs:
        if not b.is_dir():
            sys.exit(f"ERROR: not a directory: {b}")

    merge(bdirs, Path(args.out_root), force=args.force)


if __name__ == "__main__":
    main()
