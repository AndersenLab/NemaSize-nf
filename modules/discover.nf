// Discover all raw images in <data_f>/raw_images and emit a single
// newline-separated manifest of absolute paths. Sorted for deterministic
// batch numbering across resumes.

process DISCOVER_IMAGES {
    tag { data_f.name }

    input:
        path data_f

    output:
        path 'all_images.txt'

    script:
        def clean_cmd = params.clean_batches
            ? "rm -rf \"\$(readlink -f ${data_f})/batches\""
            : "true"
        """
        ${clean_cmd}

        find -L "\$(readlink -f ${data_f})/raw_images" -maxdepth 1 -type f \\
            \\( -iname '*.tif' -o -iname '*.tiff' \\
               -o -iname '*.png' \\
               -o -iname '*.jpg' -o -iname '*.jpeg' \\) \\
            | sort > all_images.txt

        n=\$(wc -l < all_images.txt)
        echo "DISCOVER_IMAGES: found \$n image(s) in ${data_f}/raw_images"
        if [ "\$n" -eq 0 ]; then
            echo "ERROR: no images matched in ${data_f}/raw_images" >&2
            exit 1
        fi
        """
}
