#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    cat >&2 <<'EOF'
Usage: ./create-test-img.sh

Creates a 10MB ext4 image, attaches it to a loop device so its UUID appears
under /dev/disk/by-uuid/, prints the UUID, and waits until interrupted
(e.g., Ctrl+C). On exit, it cleanly detaches the device and removes the image.

Options:
  -h, --help    Show this help message and exit.

Note: Requires sudo privileges.
EOF
    exit 0
fi

cd "$(dirname "$0")"

IMG_NAME="test-drive.img"
LOOP_DEV=""

cleanup() {
    local exit_code=$?

    if [[ -n "${LOOP_DEV-}" ]] && [[ -e "$LOOP_DEV" ]]; then
        echo "Detaching loop device: $LOOP_DEV" >&2
        sudo losetup -d "$LOOP_DEV" || true
    fi

    if [[ -f "$IMG_NAME" ]]; then
        echo "Removing image file: $IMG_NAME" >&2
        rm -f "$IMG_NAME"
    fi

    exit "$exit_code"
}

# Trap signals: EXIT covers normal exit, but we also explicitly trap SIGINT/SIGTERM for clarity
trap cleanup EXIT

main() {
    local size_mb=10
    local uuid

    echo "Creating ${size_mb}MB image file: $IMG_NAME" >&2
    dd if=/dev/zero of="$IMG_NAME" bs=1M count="$size_mb" status=progress

    echo "Formatting as ext4..." >&2
    mkfs.ext4 -F -q "$IMG_NAME"

    echo "Attaching to loop device..." >&2
    LOOP_DEV=$(sudo losetup --find --show "$IMG_NAME")

    udevadm settle --timeout=2 >/dev/null 2>&1 || true

    uuid=$(blkid -o value -s UUID "$LOOP_DEV")
    echo "$uuid"

    echo "Device ready. UUID is active in /dev/disk/by-uuid/." >&2
    echo "Waiting for interrupt (Ctrl+C to clean up and exit)..." >&2

    # Wait indefinitely until signal
    # sleep infinity is clean and portable (on Linux/macOS with coreutils)
    # Fallback to read if sleep infinity is unavailable
    if command -v sleep >/dev/null && sleep infinity 2>/dev/null; then
        # This will be interrupted by SIGINT/SIGTERM
        sleep infinity
    else
        # Portable fallback: read from an unopened fd (blocks forever)
        read -r < /dev/tty || true
    fi
}

main "$@"