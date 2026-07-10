// Run NemaSize on a single batch directory.
//
// Inputs : tuple(batch_id, batch_dir) where batch_dir is an absolute path to
//          <data_f>/batches/batch_<i>/ containing batch_<i>.txt.
// Outputs: tuple(batch_id, batch_dir) — emitted only after the container has
//          written inference_rois/ and NemaSize_output/ inside batch_dir.
//
// The container is the cached SIF in NXF_SINGULARITY_CACHEDIR; Nextflow rewrites
// 'zihaojohnli/nemasize:1.0.0-cpu' to <cache>/zihaojohnli-nemasize-1.0.0-cpu.img
// automatically. The batch dir is bound at the same path inside the container
// so the absolute paths inside batch_<i>.txt resolve unchanged.

process RUN_BATCH {
    tag { batch_id }

    container 'zihaojohnli/nemasize:1.0.0-cpu'
    containerOptions "--bind ${params.data_f}:${params.data_f}"

    input:
        tuple val(batch_id), val(batch_dir)

    output:
        tuple val(batch_id), val(batch_dir)

    script:
        """
        set -euo pipefail

        # skan uses @numba.jit(cache=True); without NUMBA_CACHE_DIR numba tries
        # to write next to its own source file inside the read-only container
        # image and aborts with "no locator available". Point it at a writable
        # location in the per-task work dir.
        export NUMBA_CACHE_DIR="\$PWD/.numba_cache"
        mkdir -p "\$NUMBA_CACHE_DIR"

        python /opt/nemasize/run_pipeline.py "${batch_dir}"
        """
}
