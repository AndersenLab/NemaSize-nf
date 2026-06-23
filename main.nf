// NemaSize-nf: Rockfish CPU pipeline (under construction)
//
// Current scope (step 1 of incremental rollout):
//   - DISCOVER_IMAGES: list every raw image in <data_f>/raw_images
//   - splitText:       slice the manifest into batch_<i>.txt files of size N
//
// Subsequent steps (run-batch, merge-results) will be added once this is
// verified on a small dataset.

include { DISCOVER_IMAGES } from './modules/discover.nf'
include { MAKE_BATCH_DIR  } from './modules/batch.nf'
include { RUN_BATCH       } from './modules/run_batch.nf'
include { MERGE_RESULTS   } from './modules/merge.nf'
include { CLEANUP_BATCHES } from './modules/cleanup.nf'

workflow {
    if (params.data_f == null) {
        error "Missing required parameter: --data_f <project folder containing raw_images/>"
    }
    if (params.batch_size > 25) {
        // RUN_BATCH has a 1h SLURM wall time. Empirically, 20 images takes
        // up to ~35 min on the parallel partition, so 25 is the safe upper
        // bound (~44 min worst case, ~16 min headroom). To raise this,
        // also bump time= in conf/rockfish.config under withName: RUN_BATCH.
        error "--batch_size ${params.batch_size} exceeds maximum (25). " +
              "Lower it, or raise both the cap here and the RUN_BATCH wall time in conf/rockfish.config."
    }

    ch_data = channel.value(file(params.data_f, checkIfExists: true))

    DISCOVER_IMAGES(ch_data)

    ch_manifests = DISCOVER_IMAGES.out
        .splitText(by: params.batch_size, file: 'batch_')

    ch_batch_dirs = MAKE_BATCH_DIR(ch_manifests)

    // Barrier: wait until every MAKE_BATCH_DIR has finished before any
    // RUN_BATCH submits. collect(flat: false) gathers all (id, dir) tuples
    // into a single List; flatMap re-emits them one-by-one once that List
    // arrives, so RUN_BATCH still scatters in parallel afterwards.
    ch_batches_ready = ch_batch_dirs
        .collect(flat: false)
        .flatMap()

    ch_results = RUN_BATCH(ch_batches_ready)

    // Barrier: wait for every RUN_BATCH to finish, then merge once.
    // collect() over the (id, dir) tuple keeps order deterministic by id
    // for free since all batches feed the same List.
    ch_all_dirs = ch_results
        .map { _id, dir -> dir }
        .collect()

    MERGE_RESULTS(ch_all_dirs)

    // Optional post-merge cleanup of <data_f>/batches/. Gated on merge
    // completion via MERGE_RESULTS.out so we never delete inputs of a job
    // that hasn't finished writing its outputs.
    if (params.clean_intermediate) {
        CLEANUP_BATCHES(MERGE_RESULTS.out)
        CLEANUP_BATCHES.out.view { out_root ->
            "pipeline complete: ${out_root} (intermediate batches/ removed)"
        }
    } else {
        MERGE_RESULTS.out.view { out_root ->
            "pipeline complete: ${out_root} (intermediate batches/ kept; --clean_intermediate=false)"
        }
    }
}
