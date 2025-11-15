#!/usr/bin/env bash
# backup-wrapper.sh - Run the low-level backup safely with space and cleanup logic
set -o errexit
set -o nounset
set -o pipefail

if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    cat <<'EOF'
Usage:
  Initial backup:
    ./backup-wrapper.sh --initial [-s <source-path>] <mount-point> <backup-script> <image-path> [size-MB] [extra-MB]
  Incremental backup:
    ./backup-wrapper.sh --incremental [-s <source-path>] <mount-point> <backup-script> <image-path>

Options:
  -s <path>    Source filesystem path to measure usage from (default: /)

Environment:
  MIN_RETAIN=N   Auto-clean old backups when space is low (e.g., MIN_RETAIN=3)

Requirements:
  * Run as root.
  * <mount-point> must be under /mnt/backup for safety.
  * <backup-script> must be accessible and executable.
EOF
    exit
fi

cleanup_old_images() {
    local mount_point="$1" min_retain="$2" needed_bytes="$3"
    local avail week_dirs oldest_week_dir total

    while :; do
        avail=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)

        # stop if enough space
        (( avail >= needed_bytes )) && {
            echo "[INFO] Cleanup complete: $avail bytes available (needed $needed_bytes)." >&2
            return 0
        }

        # get all week directories sorted by modification time (oldest first)
        mapfile -t week_dirs < <(
            find "$mount_point" -mindepth 2 -maxdepth 2 -type d -printf '%T@ %p\n' |
            sort -n | awk '{print $2}'
        )
        total=${#week_dirs[@]}
        (( total <= min_retain )) && {
            echo "[ERROR] Cannot free enough space — only $total week dirs, min_retain=$min_retain." >&2
            return 1
        }

        oldest_week_dir="${week_dirs[0]}"
        echo "[INFO] Not enough space ($avail < $needed_bytes), deleting oldest week directory: $oldest_week_dir" >&2

        find "$oldest_week_dir" -type f -name '*.img' -print -delete
        sync   # ensure space is committed before next df check
    done
}

check_space_or_cleanup() {
    local mount_point="$1" needed="$2" available
    available=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
    if (( available < needed )); then
        echo "[WARN] Need $needed bytes, have $available bytes." >&2
        if [[ -n "${MIN_RETAIN-}" ]]; then
            cleanup_old_images "$mount_point" "$MIN_RETAIN" "$needed" || return 1
            available=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
            (( available < needed )) && {
                echo "[ERROR] Still insufficient space after cleanup." >&2
                return 1
            }
        else
            echo "[ERROR] Set MIN_RETAIN=N to auto-clean old backups." >&2
            return 1
        fi
    fi
    echo "[INFO] Sufficient space: $available bytes (needed $needed)." >&2
}

main() {
    local mode source="/" mount_point backup_script image_path
    local init_size extra_space
    mode="$1"; shift
    if [[ "${1-}" == "-s" ]]; then
        [[ -n "${2-}" ]] || { echo "[ERROR] -s requires a path." >&2; exit 1; }
        source="$2"; shift 2
    fi
    case "$mode" in
        --initial)
            [[ $# -ge 3 ]] || { echo "[ERROR] Missing args for --initial." >&2; exit 1; }
            mount_point="$1"; backup_script="$2"; image_path="$3"
            init_size="${4-}"; extra_space="${5-}"
            ;;
        --incremental)
            [[ $# -ge 3 ]] || { echo "[ERROR] Missing args for --incremental." >&2; exit 1; }
            mount_point="$1"; backup_script="$2"; image_path="$3"
            ;;
        *)
            echo "[ERROR] Unknown mode: $mode" >&2
            exit 1
            ;;
    esac

    if ! [[ "$mount_point" =~ ^/mnt/backup(/|$) ]]; then
        echo "[ERROR] mount-point '$mount_point' must be under /mnt/backup for safety." >&2
        exit 1
    fi
    local available used needed
    available=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
    used=$(df --block-size=1 --output=used "$source" | tail -n +2)
    needed=$((used + used / 16))
    check_space_or_cleanup "$mount_point" "$needed"
    [[ -f "$backup_script" ]] || { echo "[ERROR] Backup script missing: $backup_script" >&2; exit 1; }
    if [[ "$mode" == "--initial" ]]; then
        local args="$image_path"
        [[ -n "$init_size" ]] && args+=",$init_size"
        [[ -n "$extra_space" ]] && args+=",$extra_space"
        echo "[INFO] Running: bash \"$backup_script\" -i \"$args\"" >&2
        bash "$backup_script" -i "$args"
    else
        echo "[INFO] Running: bash \"$backup_script\" \"$image_path\"" >&2
        bash "$backup_script" "$image_path"
    fi
}

cd "$(dirname "$0")"
main "$@"