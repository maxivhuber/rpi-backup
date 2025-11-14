#!/usr/bin/env bash
# create-test-img.sh - Creates a temporary XFS loop device for testing
set -o errexit
set -o nounset
set -o pipefail

if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    cat <<'EOF'
Usage: ./create-test-img.sh
Creates a 512MB XFS image, attaches it to a loop device so its UUID appears
under /dev/disk/by-uuid/, prints the UUID, and waits until interrupted
(e.g., Ctrl+C). On exit, it cleanly detaches the device and removes the image.

Options:
  -h, --help    Show this help message and exit.

Note: Run this script as root (or with sudo).
EOF
    exit 0
fi

cd "$(dirname "$0")"


IMG_NAME="test-drive.img"
LOOP_DEV=""

cleanup() {
    local exit_code=$?

    if [[ -n "${LOOP_DEV-}" ]] && [[ -e "$LOOP_DEV" ]]; then
        echo "[CLEANUP] Detaching loop device: $LOOP_DEV" >&2
        losetup -d "$LOOP_DEV" || true
    fi
    if [[ -f "$IMG_NAME" ]]; then
        echo "[CLEANUP] Removing image file: $IMG_NAME" >&2
        rm -f "$IMG_NAME"
    fi
    return "$exit_code"
}

trap cleanup EXIT

main() {
    # Variables that are constants within the function.
    local size_mb=512
    local uuid

    echo "[INFO] Creating ${size_mb}MB image file: $IMG_NAME" >&2
    dd if=/dev/zero of="$IMG_NAME" bs=1M count="$size_mb" status=progress

    echo "[INFO] Formatting as XFS..." >&2
    mkfs.xfs -f -q "$IMG_NAME"

    echo "[INFO] Attaching to loop device..." >&2
    LOOP_DEV=$(losetup --find --show "$IMG_NAME")

    # Wait for udev to process the new device node
    udevadm settle --timeout=2 >/dev/null 2>&1 || true

    uuid=$(blkid -o value -s UUID "$LOOP_DEV")

    # Print the UUID to standard output, as this is the script's primary result.
    echo "$uuid"

    echo "[INFO] Device ready. UUID is active in /dev/disk/by-uuid/." >&2
    echo "[INFO] Waiting for interrupt (Ctrl+C to clean up and exit)..." >&2

    # Wait indefinitely until interrupted.
    # This is a robust way to sleep forever across different systems.
    if command -v sleep >/dev/null && sleep infinity 2>/dev/null; then
        sleep infinity
    else
        # Fallback for systems without 'sleep infinity'
        read -r < /dev/tty || true
    fi
}

main "$@"