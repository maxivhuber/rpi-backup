# Backup Testing Instructions

## How to Use

### For testing:

To quickly set up a dummy backup device for testing:

1. Create a dummy test image:
   ```bash
   sudo bash create-test-img.sh
   ```
   This creates a **dummy backup device** and prints the **UUID** on the last line.

2. Run the initial backup test using the wrapper:
   ```bash
   sudo bash backup-wrapper.sh --initial ...
   ```
   *(See details below for full usage examples.)*
---

## `dummy_backup.sh`

The `dummy_backup.sh` script is the **low-level backup test script**.  
If you want to run it directly, you must first mount the dummy device created earlier.

### Setup

1. Create and mount the dummy device:
   ```bash
   sudo bash create-test-img.sh
   sudo mount -U <UUID> /mnt/backup
   ```

2. Run one of the following test modes:

### Example – Direct Script Usage

**Initial Backup:**
```bash
bash dummy_backup.sh -i ./mnt/backup/46/2025/rpi.img,2048,512
```

**Incremental Backup:**
```bash
bash dummy_backup.sh ./mnt/backup/46/2025/rpi.img
```

---

## `backup-wrapper.sh`

Alternatively, you can use the **wrapper script** `backup-wrapper.sh`, which provides additional control and wraps `dummy_backup.sh`.

This approach **does not require mounting the UUID manually** — the wrapper handles that automatically.

### Example – Wrapper Script Usage

**Initial Backup Wrapper Example:**
```bash
bash backup-wrapper.sh \
    --initial \
    -s ./mnt/backup \
    ./mnt/backup \
    b17403dd-f4b3-4601-9514-f3bb56e90735 \
    dummy_backup.sh \
    ./mnt/backup/46/2025/rpi.img \
    2048 \
    512
```

**Incremental Backup Wrapper Example:**
```bash
bash backup-wrapper.sh \
    --incremental \
    -s ./mnt/backup \
    ./mnt/backup \
    b17403dd-f4b3-4601-9514-f3bb56e90735 \
    dummy_backup.sh \
    ./mnt/backup/46/2025/rpi.img
```

In these examples:
- The UUID (`b17403dd-f4b3-4601-9514-f3bb56e90735`) is passed directly as an argument.
- The `-s` parameter is used to override the **source directory** (where backups originate).

---

## Notes

- Manual UUID mounting is **only required when using `dummy_backup.sh` directly**.
- The wrapper (`backup-wrapper.sh`) can handle the mounted device for you.
- Replace placeholder paths and UUIDs with real values for your setup.
- Use `--initial` for a full first-time backup and `--incremental` to update an existing backup incrementally.
- These scripts are intended for **testing and debugging** your backup logic.

---