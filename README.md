# Backup Testing Instructions

This project provides scripts to test and automate Raspberry Pi image backups.  
You can simulate backups with a dummy image or run real scheduled backups via systemd.

---

## Quick Test Setup

1. **Create a dummy backup device**
   ```
   sudo bash create-test-img.sh
   ```
   Prints a fake but usable device UUID on the last line.

2. **Run a sample (initial) backup**
   ```
   sudo MIN_RETAIN=2 bash backup-wrapper.sh --initial ...
   ```
   (See usage examples below for options.)

---

## `dummy_backup.sh`

Low‑level test backup script — works directly on a mounted dummy device.

### Setup
```
sudo bash create-test-img.sh
sudo mount -U <UUID> /mnt/backup
```

### Run Examples
```
# Full (initial) backup
bash scripts/dummy_backup.sh -i /mnt/backup/46/2025/rpi.img,2048,512

# Incremental update
bash scripts/dummy_backup.sh /mnt/backup/46/2025/rpi.img
```

---

## `backup-wrapper.sh`

High‑level wrapper around `dummy_backup.sh` that handles space checks and retention cleanup.  
Mounting the drive manually is not required.

### Example – Initial Backups
```
for i in {1..30}; do
  echo "[$i] Running backup (week $i)..."
  sudo MIN_RETAIN=2 bash scripts/backup-wrapper.sh \
    --initial -s /mnt/backup /mnt/backup dummy_backup.sh \
    /mnt/backup/$i/2025/rpi.img 2048 512
  echo
done
```

### Example – Incremental Backups
```
for i in {1..30}; do
  echo "[$i] Running incremental backup..."
  sudo MIN_RETAIN=2 bash scripts/backup-wrapper.sh \
    --incremental -s /mnt/backup /mnt/backup dummy_backup.sh \
    /mnt/backup/30/2025/rpi.img
  echo
done
```

Notes:
- `MIN_RETAIN=2` keeps the two newest backups.
- `-s` overrides the source path to measure space usage. Usally /. 

---

## Real Backups via systemd

1. **Clone**
   ```
   git clone https://github.com/seamusdemora/RonR-RPi-image-utils.git
   cd RonR-RPi-image-utils
   ```

2. **Configure `rpi-backup.sh`**
   ```
   WRAPPER="scripts/backup-wrapper.sh"
   BACKUP_SCRIPT="scripts/dummy_backup.sh"   # change to the real backup script if needed
   SRC="/"                     # source filesystem
   MOUNT_PT="/mnt/backup"      # external SSD mount point
   UUID="<your-SSD-UUID>"      # from create-test-img.sh or lsblk -f
   INIT_SIZE_MB=8192
   EXTRA_MB=512
   MIN_RETAIN=2
   ```

3. **Install service and timers**
   ```
   sudo cp rpi-backup*.service rpi-backup*.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   ```

4. **Enable timers**
   ```
   sudo systemctl enable --now rpi-backup-weekly.timer
   sudo systemctl enable --now rpi-backup-12h.timer
   ```

5. **Check active timers**
   ```
   systemctl list-timers rpi-backup*
   ```

6. **Run manually (one‑time test)**
   ```
   sudo systemctl start rpi-backup.service
   ```

7. **Verify results and logs**
   ```
   sudo ls -l /mnt/backup
   sudo journalctl -u rpi-backup.service -e
   ```

Summary:
- `rpi-backup-weekly.timer` → full backup every Sunday at 03:00  
- `rpi-backup-12h.timer` → incremental backup every 12 hours  
- `rpi-backup.service` → can be started manually anytime

---

## Notes

- Manual UUID mounting is only needed when using `dummy_backup.sh` directly.  
  The wrapper and service handle mounting for you.
- Replace placeholder paths and UUIDs with your real setup.
- Set `MIN_RETAIN` to adjust how many old backups are kept.
- Use `--initial` for the first full backup, `--incremental` for updates.
- Scripts are designed for testing and debugging of backup logic.