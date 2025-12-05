#!/usr/bin/env bash
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
    ./backup-wrapper.sh --initial [-s <source-path>] [-S <size-MB>] [-E <extra-MB>] [-o <opts>] <mount-point> <backup-script> <image-path>
  Incremental backup:
    ./backup-wrapper.sh --incremental [-s <source-path>] [-o <opts>] <mount-point> <backup-script> <image-path>
Options:
  -s <path>    Source filesystem path to measure usage from (default: /)
  -S <size>    Initial image size in MB (optional)
  -E <extra>   Extra space in MB to allocate (optional)
  -o <opts>    Comma-separated rsync-style options (passed through)
Environment:
  MIN_RETAIN=N   Auto-clean old backups when space is low
Requirements:
  Must run as root. <mount-point> must be under /mnt/backup.
EOF
    exit 0
fi
cleanup_old_images() {
    local mount_point="$1" min_retain="$2" needed="$3"
    local avail week_dirs total oldest
    while true; do
        avail=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
        (( avail >= needed )) && {
            echo "[INFO] Cleanup complete: have $avail bytes, need $needed." >&2
            return 0
        }
        mapfile -t week_dirs < <(
            find "$mount_point" -mindepth 2 -maxdepth 2 -type d -printf '%T@ %p\n' |
            sort -n |
            awk '{print $2}'
        )
        total=${#week_dirs[@]}
        (( total <= min_retain )) && {
            echo "[ERROR] Only $total week dirs left; min_retain=$min_retain. Cannot free more space." >&2
            return 1
        }
        oldest="${week_dirs[0]}"
        echo "[INFO] Not enough space; deleting oldest: $oldest" >&2
        find "$oldest" -type f -name '*.img' -print -delete
        sync
    done
}
check_space_or_cleanup() {
    local mount_point="$1" needed="$2" avail
    avail=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
    if (( avail < needed )); then
        echo "[WARN] Need $needed bytes, have $avail." >&2
        if [[ -n "${MIN_RETAIN-}" ]]; then
            cleanup_old_images "$mount_point" "$MIN_RETAIN" "$needed" || return 1
            avail=$(df --block-size=1 --output=avail "$mount_point" | tail -n +2)
            (( avail < needed )) && {
                echo "[ERROR] Still insufficient space after cleanup." >&2
                return 1
            }
        else
            echo "[ERROR] Not enough space. Set MIN_RETAIN=N for auto-clean." >&2
            return 1
        fi
    fi
    echo "[INFO] Sufficient space: $avail bytes (needed $needed)." >&2
}
main() {
    local mode source="/" mount_point backup_script image_path
    local init_size="" extra_space=""
    local -a OPTIONS=()
    if [[ $# -lt 1 ]]; then
        echo "[ERROR] Missing mode (--initial or --incremental)." >&2
        exit 1
    fi
    mode="$1"
    shift
    while [[ $# -gt 0 && "${1-}" == -* ]]; do
        case "$1" in
            -s)
                [[ -z "${2-}" ]] && { echo "[ERROR] -s requires a path." >&2; exit 1; }
                source="$2"
                shift 2
                ;;
            -S)
                [[ -z "${2-}" ]] && { echo "[ERROR] -S requires a size." >&2; exit 1; }
                init_size="$2"
                shift 2
                ;;
            -E)
                [[ -z "${2-}" ]] && { echo "[ERROR] -E requires extra space." >&2; exit 1; }
                extra_space="$2"
                shift 2
                ;;
            -o|--options)
                local raw="${2-}"
                IFS=',' read -ra tmp <<< "$raw"
                for t in "${tmp[@]}"; do
                    OPTIONS+=( "--$t" )
                done
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done
    case "$mode" in
        --initial|--incremental)
            if [[ $# -lt 3 ]]; then
                echo "[ERROR] Missing arguments: <mount-point> <backup-script> <image-path>" >&2
                exit 1
            fi
            mount_point="$1"
            backup_script="$2"
            image_path="$3"
            ;;
        *)
            echo "[ERROR] Unknown mode: $mode" >&2
            exit 1
            ;;
    esac
    if ! [[ "$mount_point" =~ ^/mnt/backup(/|$) ]]; then
        echo "[ERROR] mount-point must be under /mnt/backup." >&2
        exit 1
    fi
    local used needed
    used=$(df --block-size=1 --output=used "$source" | tail -n +2)
    needed=$(( used + used / 16 ))
    check_space_or_cleanup "$mount_point" "$needed"
    [[ -f "$backup_script" ]] || {
        echo "[ERROR] Backup script missing: $backup_script" >&2
        exit 1
    }
    local opts=""
    if (( ${#OPTIONS[@]} > 0 )); then
        opts=$(printf "%s," "${OPTIONS[@]}" | sed 's/,$//')
    fi
    if [[ "$mode" == "--initial" ]]; then
        local args="$image_path,${init_size},${extra_space}"
        printf -v pretty_opts '%s ' "${OPTIONS[@]}"
        echo "[INFO] Running INITIAL: bash \"$backup_script\" -i \"$args\" ${pretty_opts:+-o \"$pretty_opts\"}" >&2
        if [[ -n "$opts" ]]; then
            bash "$backup_script" -i "$args" -o "$opts"
        else
            bash "$backup_script" -i "$args"
        fi
    else
        printf -v pretty_opts '%s ' "${OPTIONS[@]}"
        echo "[INFO] Running INCREMENTAL: bash \"$backup_script\" ${pretty_opts:+-o \"$pretty_opts\"} \"$image_path\"" >&2
        if [[ -n "$opts" ]]; then
            bash "$backup_script" -o "$opts" "$image_path"
        else
            bash "$backup_script" "$image_path"
        fi
    fi
}
cd "$(dirname "$0")"
main "$@"