#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi
if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    cat <<'EOF'
Usage: ./rpi-backup.sh
Automated image backup wrapper:
    Performs a new full backup once a week.
    Performs incremental updates every 12 hours.
    Before each incremental update, makes a reflink snapshot of the
    current image file for version history.
Requirements:
    The backup drive must be formatted with a reflink‑capable filesystem
    (XFS, Btrfs, or similar). The script exits if not.
Enable debug tracing with:
  TRACE=1 ./rpi-backup.sh
EOF
    exit 0
fi
cd "$(dirname "$0")"
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Try: sudo $0" >&2
    exit 1
fi
# Configurable parameters
WRAPPER="/opt/rpi-backup/scripts/backup-wrapper.sh"      # High-level wrapper that manages space + retention
BACKUP_SCRIPT="/opt/RonR-RPi-image-utils/image-backup"   # Actual image creation script (RonR RPi utility)
SRC="/"                                                  # Filesystem to measure usage from
MOUNT_PT="/mnt/backup"                                   # Mount point of backup SSD
UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"              # UUID of the backup SSD
INIT_SIZE_MB=""                                          # Initial image size in MB (optional)
EXTRA_MB="1024"                                          # Extra MB to allocate inside initial images
MIN_RETAIN="3"                                           # Minimum weekly backups to retain
MOUNTED=0                                                # Set to 1 when SSD is mounted
EXCLUDES="exclude=/tmp,exclude=/var/log"                 # Excludes passed to backup-wrapper (-o)
cleanup() {
    local exit_code=$?
    if [[ $MOUNTED -eq 1 && -d "$MOUNT_PT" && -e "/dev/disk/by-uuid/$UUID" ]]; then
        if mountpoint -q "$MOUNT_PT"; then
            echo "[CLEANUP] Unmounting SSD from $MOUNT_PT..." >&2
            umount "$MOUNT_PT" || echo "[WARN] Failed to unmount $MOUNT_PT" >&2
        fi
        echo "[CLEANUP] Removing empty directories under $MOUNT_PT..." >&2
        find "$MOUNT_PT" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    fi
    return "$exit_code"
}
trap cleanup EXIT
check_reflink_fs() {
    local mount_point="$1"
    local fstype
    if ! fstype=$(stat -f -c %T "$mount_point" 2>/dev/null); then
        echo "[ERROR] Cannot determine filesystem type of '$mount_point'." >&2
        exit 1
    fi
    case "$fstype" in
        xfs|btrfs)
            echo "[INFO] Filesystem '$fstype' supports reflinks — OK."
            ;;
        *)
            echo "[ERROR] Filesystem '$fstype' under '$mount_point' does not support reflinks!" >&2
            echo "[ERROR] Please reformat the backup drive as XFS or Btrfs." >&2
            exit 1
            ;;
    esac
}
mount_ssd() {
    if [[ ! -e "/dev/disk/by-uuid/$UUID" ]]; then
        echo "[ERROR] External SSD not connected (UUID=$UUID)." >&2
        exit 1
    fi
    if ! mountpoint -q "$MOUNT_PT"; then
        echo "[INFO] Mounting SSD..." >&2
        mount "/dev/disk/by-uuid/$UUID" "$MOUNT_PT"
        MOUNTED=1
    else
        MOUNTED=1
    fi
}
main() {
    local week year week_dir img_path timestamp snapshot dow
    mount_ssd
    check_reflink_fs "$MOUNT_PT"
    week=$(date +%V)
    year=$(date +%Y)
    week_dir="${MOUNT_PT}/${week}/${year}"
    img_path="${week_dir}/rpi.img"
    timestamp=$(date +%Y-%m-%d_%H%M)
    snapshot="${week_dir}/rpi_${timestamp}.img"
    mkdir -p "$week_dir"
    dow=$(date +%u)
    if [[ "$dow" == "7" || ! -f "$img_path" ]]; then
        echo "[INFO] Creating initial full backup for week $week $year..."
        env MIN_RETAIN="$MIN_RETAIN" bash "$WRAPPER" --initial \
            -s "$SRC" \
            -o "$EXCLUDES" \
            ${INIT_SIZE_MB:+-S "$INIT_SIZE_MB"} \
            ${EXTRA_MB:+-E "$EXTRA_MB"} \
            "$MOUNT_PT" \
            "$BACKUP_SCRIPT" \
            "$img_path"
    else
        echo "[INFO] Performing incremental backup for week $week $year..."
        if [[ -f "$img_path" ]]; then
            echo "[INFO] Creating snapshot: $snapshot"
            cp --reflink=auto "$img_path" "$snapshot"
        fi
        env MIN_RETAIN="$MIN_RETAIN" bash "$WRAPPER" --incremental \
            -s "$SRC" \
            -o "$EXCLUDES" \
            "$MOUNT_PT" \
            "$BACKUP_SCRIPT" \
            "$img_path"
    fi
}
main "$@"