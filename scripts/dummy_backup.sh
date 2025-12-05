#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi
if [[ "${1-}" =~ ^-*h(elp)?$ || "${1-}" == "help" ]]; then
    cat >&2 << 'EOF'
Usage:
  Initial:     ./image-backup.sh -i -o <opts> <image-path>[,<size-MB>[,<extra-MB>]]
  Incremental: ./image-backup.sh -o <opts> <image-path>
<opts> = Comma‑separated list of rsync‑style options
         (ignored here, accepted only for API compatibility)
In initial mode, creates an 8MB dummy file.
In incremental mode, appends 512KB to the file.
EOF
    exit 0
fi
cd "$(dirname "$0")"
main() {
    local image_path size_mb extra_mb mode
    local -a OPTIONS=()
    while [[ "${1-}" != "" ]]; do
        case "$1" in
            -i|--initial)
                mode="initial"
                shift
                ;;
            -o|--options)
                local raw_opts="${2-}"
                IFS=',' read -ra tmp_opts <<< "$raw_opts"
                OPTIONS+=("${tmp_opts[@]}")
                shift 2
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                if [[ "${mode-}" == "initial" ]]; then
                    IFS=',' read -r image_path size_mb extra_mb <<< "$1"
                else
                    mode="incremental"
                    image_path="$1"
                fi
                shift
                ;;
        esac
    done
    if [[ -z "${mode-}" ]]; then
        mode="incremental"
    fi
    if [[ -z "${image_path-}" ]]; then
        echo "Error: image_path is empty" >&2
        exit 1
    fi
    echo "mode=$mode"
    echo "image_path=$image_path"
    echo "size_mb=${size_mb-}"
    echo "extra_mb=${extra_mb-}"
    echo "options=${OPTIONS[*]-}"
    if [[ "$mode" == "initial" ]]; then
        mkdir -p "$(dirname "$image_path")"
        echo "Creating 8MB dummy file at $image_path" >&2
        dd if=/dev/zero of="$image_path" bs=1M count=8 status=none
    else
        echo "Appending 512KB to $image_path" >&2
        if [[ ! -f "$image_path" ]]; then
            echo "Error: file does not exist for incremental update: $image_path" >&2
            exit 1
        fi
        dd if=/dev/zero of="$image_path" bs=1024 count=512 status=none oflag=append conv=notrunc
    fi
}
main "$@"