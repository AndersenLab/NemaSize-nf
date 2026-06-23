// Remove the per-batch intermediate folder once MERGE_RESULTS has produced
// the unified <data_f>/NemaSize_output/. Runs only after merge completes.
//
// The whole batches/ tree is disposable: it holds only the splitText
// manifests (regenerable from raw_images) and per-batch outputs (already
// consolidated by merge_results.py).

process CLEANUP_BATCHES {
    tag { "cleanup" }

    input:
        val out_root   // from MERGE_RESULTS; used purely as a happens-after gate

    output:
        val out_root

    script:
        def batches_dir = "${params.data_f}/batches"
        """
        if [ -d "${batches_dir}" ]; then
            rm -rf "${batches_dir}"
            echo "CLEANUP_BATCHES: removed ${batches_dir}"
        else
            echo "CLEANUP_BATCHES: ${batches_dir} not present, nothing to do"
        fi
        """
}
