// Wrap each batch manifest from splitText in its own folder under
// <data_f>/batches/. Writes the folder directly to the final location so
// there's no duplicate copy in Nextflow's work/ tree.
//
//   <data_f>/batches/
//     batch_<i>/
//       batch_<i>.txt   ← absolute image paths for this batch
//
// This is the unit RUN_BATCH will consume later: it can mount batch_<i>/
// into the container and write its outputs alongside the manifest.

process MAKE_BATCH_DIR {
    tag { batch_id }

    input:
        path manifest

    output:
        tuple val(batch_id), val(batch_dir)

    script:
        // splitText names files batch_.1, batch_.2, ... — strip the prefix
        // (and the leading dot) to get a clean numeric id.
        batch_id  = manifest.name.replaceFirst(/^batch_\.?/, '')
        batch_dir = "${params.data_f}/batches/batch_${batch_id}"
        """
        mkdir -p "${batch_dir}"
        cp -f "${manifest}" "${batch_dir}/batch_${batch_id}.txt"
        """
}
