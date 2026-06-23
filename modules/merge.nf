// Merge per-batch NemaSize outputs into a single <data_f>/NemaSize_output/.
//
// Runs after every RUN_BATCH has finished (the workflow uses .collect() to
// build the barrier). Fast, local — invokes a python script bundled under
// bin/ which Nextflow auto-adds to PATH for the task.

process MERGE_RESULTS {
    tag { "merge" }

    input:
        val batch_dirs   // list of absolute batch_<i>/ paths

    output:
        val out_root

    script:
        out_root  = "${params.data_f}/NemaSize_output"
        def force = params.force_merge ? '--force' : ''
        def args  = batch_dirs.collect { "\"${it}\"" }.join(' ')
        """
        python "\$(command -v merge_results.py)" --out-root "${out_root}" ${force} ${args}
        """
}
