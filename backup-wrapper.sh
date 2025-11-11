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
  Initial:     ./backup-wrapper.sh --initial <mount-point> <uuid> <backup-script> <image-path> [size-MB] [extra-MB]
  Incremental: ./backup-wrapper.sh --incremental <mount-point> <uuid> <backup-script> <image-path>

Optional:
  Set MIN_RETAIN=N in environment to auto-clean old backups when space is low (e.g., MIN_RETAIN=3).

Runs RonR-RPi-image-utils/image-backup with space and mount validation.
EOF
    exit 0
fi

cd "$(dirname "$0")"

cleanup_old_images() {
    local mount_point="$1"
    local min_retain="$2"
    local needed_bytes="$3"

    local available_bytes
    available_bytes=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)

    # Already enough space? Nothing to do.
    if (( available_bytes >= needed_bytes )); then
        return 0
    fi

    local to_free=$((needed_bytes - available_bytes))
    local freed=0
    local files_to_delete=()
    local all_files=()
    local file

    # Recursively collect all regular files under mount_point, oldest first
    while IFS= read -r -d '' file; do
        all_files+=("$file")
    done < <(find "$mount_point" -type f -print0 | LC_ALL=C sort -z)

    local total_files=${#all_files[@]}
    if (( total_files == 0 )); then
        echo "No files found to clean up under $mount_point." >&2
        return 1
    fi

    # Respect min_retain: max deletable = total - min_retain
    local max_deletable=$((total_files - min_retain))
    if (( max_deletable <= 0 )); then
        echo "Cannot delete any files: min_retain ($min_retain) >= total files ($total_files)." >&2
        return 1
    fi

    # Iterate from oldest (index 0) upward until we've freed enough OR hit max_deletable
    local i=0
    while (( i < total_files && i < max_deletable && freed < to_free )); do
        file="${all_files[i]}"
        if [[ -f "$file" ]]; then
            local size
            size=$(stat -c '%s' "$file" 2>/dev/null) || continue
            files_to_delete+=("$file")
            ((freed += size))
        fi
        ((i++))
    done

    # Check if we freed enough
    if (( freed < to_free )); then
        echo "Cannot free enough space: need $to_free bytes, can only free $freed bytes (min_retain=$min_retain)." >&2
        return 1
    fi

    # Safety: ensure we won't violate min_retain
    local to_delete_count=${#files_to_delete[@]}
    if (( total_files - to_delete_count < min_retain )); then
        echo "BUG: Cleanup would violate min_retain. Aborting." >&2
        return 1
    fi

    # Perform deletion
    echo "Cleaning up $to_delete_count old file(s) to free space..." >&2
    for file in "${files_to_delete[@]}"; do
        echo "Deleting: $file" >&2
        rm -f "$file"
    done

    return 0
}

main() {
    local mode mount_point uuid backup_script image_path initial_size incremental_space
    local available_space current_usage needed_space

    if [[ $# -lt 1 ]]; then
        echo "Error: Mode (--initial or --incremental) required. See --help" >&2
        exit 1
    fi

    mode="$1"; shift

    if [[ "$mode" == "--initial" ]]; then
        if [[ $# -lt 4 ]]; then
            echo "Error: --initial requires: mount-point uuid backup-script image-path [size] [extra]" >&2
            exit 1
        fi
        mount_point="$1"; uuid="$2"; backup_script="$3"; image_path="$4"
        initial_size="${5-}"; incremental_space="${6-}"
    elif [[ "$mode" == "--incremental" ]]; then
        if [[ $# -lt 4 ]]; then
            echo "Error: --incremental requires: mount-point uuid backup-script image-path" >&2
            exit 1
        fi
        mount_point="$1"; uuid="$2"; backup_script="$3"; image_path="$4"
    else
        echo "Error: First argument must be --initial or --incremental" >&2
        exit 1
    fi

    # Validate device
    if [[ ! -e "/dev/disk/by-uuid/$uuid" ]]; then
        echo "External SSD not connected." >&2
        exit 1
    fi

    # Mount if needed
    if ! mountpoint -q "$mount_point"; then
        echo "Mounting SSD..." >&2
        if ! sudo mount "/dev/disk/by-uuid/$uuid" "$mount_point"; then
            echo "Failed to mount SSD." >&2
            exit 1
        fi
    fi

    # Space check
    available_space=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
    current_usage=$(df --block-size=1 --output=used / | tail -n +2)
    needed_space=$((current_usage + (current_usage / 16)))

    if (( available_space < needed_space )); then
        echo "Not enough space: need ${needed_space} bytes, only have ${available_space} bytes" >&2

        if [[ -n "${MIN_RETAIN-}" ]]; then
            if ! cleanup_old_images "$mount_point" "$MIN_RETAIN" "$needed_space"; then
                echo "Cleanup failed or insufficient space even after cleanup." >&2
                exit 1
            fi

            # Re-check space after cleanup
            available_space=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
            if (( available_space < needed_space )); then
                echo "Still not enough space after cleanup." >&2
                exit 1
            fi
        else
            echo "Set MIN_RETAIN=N (e.g., MIN_RETAIN=3) to auto-clean old backups." >&2
            exit 1
        fi
    fi

    echo "Sufficient space available: ${available_space} bytes (need ${needed_space} bytes)" >&2

    # Validate backup script
    if [[ ! -f "$backup_script" ]]; then
        echo "Backup script not found: $backup_script" >&2
        exit 1
    fi

    # Build args for backup script
    if [[ "$mode" == "--initial" ]]; then
        local initial_arg="$image_path"
        if [[ -n "$initial_size" ]]; then
            initial_arg="$initial_arg,$initial_size"
            if [[ -n "$incremental_space" ]]; then
                initial_arg="$initial_arg,$incremental_space"
            fi
        fi
        exec sudo "$backup_script" -i "$initial_arg"
    else
        exec sudo "$backup_script" "$image_path"
    fi
}

main "$@"