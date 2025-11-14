#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    cat >&2 << 'EOF'
Usage:
  Initial:     ./image-backup.sh -i <image-path>[,<size-MB>[,<extra-MB>]]
  Incremental: ./image-backup.sh <image-path>

In initial mode, creates a 8MB dummy file.
In incremental mode, appends 512KB to the file.
EOF
    exit 0
fi

cd "$(dirname "$0")"

main() {
    local image_path size_mb extra_mb mode

    if [[ "${1-}" == "-i" ]]; then
        mode="initial"
        IFS=',' read -r image_path size_mb extra_mb <<< "${2-}"
    else
        mode="incremental"
        image_path="${1-}"
    fi

    # Validate image_path is non-empty
    if [[ -z "$image_path" ]]; then
        echo "Error: image_path is empty" >&2
        exit 1
    fi

    echo "mode=$mode"
    echo "image_path=$image_path"
    echo "size_mb=${size_mb-}"
    echo "extra_mb=${extra_mb-}"

    if [[ "$mode" == "initial" ]]; then
        # Ensure parent directory exists
        mkdir -p "$(dirname "$image_path")"

        # Create a 8MB dummy file (filled with zeros)
        echo "Creating 8MB dummy file at $image_path" >&2
        dd if=/dev/zero of="$image_path" bs=1M count=8 status=none
    else
        # Append 512KB (524288 bytes = 512 * 1024)
        echo "Appending 512KB to $image_path" >&2
        if [[ ! -f "$image_path" ]]; then
            echo "Error: file does not exist for incremental update: $image_path" >&2
            exit 1
        fi
        dd if=/dev/zero of="$image_path" bs=1024 count=512 status=none oflag=append conv=notrunc
    fi
}

main "$@"