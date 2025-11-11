#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then set -o xtrace; fi

# Global vars for cleanup
MOUNT_POINT=""
UUID=""

cleanup() {
    local exit_code=$?
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" && -e "/dev/disk/by-uuid/$UUID" ]]; then
        if mountpoint -q "$MOUNT_POINT"; then
            echo "Unmounting SSD from $MOUNT_POINT..." >&2
            sudo umount "$MOUNT_POINT" || echo "Warning: Failed to unmount $MOUNT_POINT" >&2
        fi
    fi
    exit "$exit_code"
}
trap cleanup EXIT

show_help() {
    cat >&2 <<'EOF'
Usage:
  Initial:     ./backup-wrapper.sh --initial [-s <source-path>] <mount-point> <uuid> <backup-script> <image-path> [size-MB] [extra-MB]
  Incremental: ./backup-wrapper.sh --incremental [-s <source-path>] <mount-point> <uuid> <backup-script> <image-path>

Options:
  -s <path>    Source filesystem path to measure usage from (default: /)
Environment:
  MIN_RETAIN=N  Auto-clean old backups when space is low (e.g., MIN_RETAIN=3)

Runs RonR-RPi-image-utils/image-backup with space and mount validation.
EOF
    exit 0
}

cleanup_old_images() {
    local mount_point="$1" min_retain="$2" needed_bytes="$3"
    local avail to_free freed=0
    avail=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
    (( avail >= needed_bytes )) && return 0

    to_free=$((needed_bytes - avail))
    mapfile -t all_files < <(sudo find "$mount_point" -type f -printf '%T@ %p\n' | sort -n | awk '{print $2}')
    
    local total=${#all_files[@]}
    local max_deletable=$((total - min_retain))
    (( total == 0 || max_deletable <= 0 )) && {
        echo "No deletable files (min_retain=$min_retain, total=$total)." >&2
        return 1
    }

    local files_to_delete=() size file
    for (( i=0; i<max_deletable && freed<to_free; i++ )); do
        file="${all_files[i]}"
        (( size=$(stat -c '%s' "$file" 2>/dev/null || echo 0) )) || continue
        files_to_delete+=("$file")
        (( freed += size ))
    done

    (( freed < to_free )) && {
        echo "Cannot free enough space (need=$to_free, can free=$freed)." >&2
        return 1
    }

    echo "Cleaning ${#files_to_delete[@]} old file(s) to free space..." >&2
    for file in "${files_to_delete[@]}"; do
        echo "Deleting: $file" >&2
        sudo rm -f "$file"
    done
}

check_space_or_cleanup() {
    local mount_point="$1" needed="$2" available
    available=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
    if (( available < needed )); then
        echo "Need $needed bytes, have $available bytes." >&2
        if [[ -n "${MIN_RETAIN-}" ]]; then
            cleanup_old_images "$mount_point" "$MIN_RETAIN" "$needed" || return 1
            available=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
            (( available < needed )) && {
                echo "Still insufficient space after cleanup." >&2; return 1; }
        else
            echo "Set MIN_RETAIN=N to auto-clean old backups." >&2; return 1
        fi
    fi
    echo "Sufficient space: $available bytes (needed $needed)." >&2
}

main() {
    local mode source="/" mount_point uuid backup_script image_path
    local init_size="${6-}" extra_space="${7-}"
    [[ $# -eq 0 || "${1-}" =~ ^-*h(elp)?$ ]] && show_help

    mode="$1"; shift
    if [[ "${1-}" == "-s" ]]; then
        [[ -n "${2-}" ]] || { echo "Error: -s requires a path." >&2; exit 1; }
        source="$2"; shift 2
    fi

    case "$mode" in
        --initial)
            [[ $# -ge 4 ]] || { echo "Error: Missing arguments for --initial." >&2; exit 1; }
            mount_point="$1"; uuid="$2"; backup_script="$3"; image_path="$4"
            init_size="${5-}"; extra_space="${6-}"
            ;;
        --incremental)
            [[ $# -ge 4 ]] || { echo "Error: Missing arguments for --incremental." >&2; exit 1; }
            mount_point="$1"; uuid="$2"; backup_script="$3"; image_path="$4"
            ;;
        *) echo "Error: Mode must be --initial or --incremental" >&2; exit 1 ;;
    esac

    MOUNT_POINT="$mount_point"; UUID="$uuid"

    df --block-size=1 "$source" >/dev/null 2>&1 || { echo "Invalid source path: $source" >&2; exit 1; }
    [[ -e "/dev/disk/by-uuid/$uuid" ]] || { echo "External SSD not connected." >&2; exit 1; }

    mountpoint -q "$mount_point" || { echo "Mounting SSD..." >&2; sudo mount "/dev/disk/by-uuid/$uuid" "$mount_point"; }

    local available used needed
    available=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
    used=$(df --block-size=1 --output=used "$source" | tail -n +2)
    needed=$((used + used / 16))

    check_space_or_cleanup "$mount_point" "$needed"

    [[ -f "$backup_script" ]] || { echo "Backup script missing: $backup_script" >&2; exit 1; }

    if [[ "$mode" == "--initial" ]]; then
        local args="$image_path"
        [[ -n "$init_size" ]] && args+=",$init_size"
        [[ -n "$extra_space" ]] && args+=",$extra_space"
        sudo bash "./$backup_script" -i "$args"
    else
        sudo bash "$backup_script" "$image_path"
    fi
}

cd "$(dirname "$0")"
main "$@"