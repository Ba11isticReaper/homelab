#!/bin/bash
# Nightly backup of irreplaceable data to the external USB drive.
# Run by backup-family.service, scheduled by backup-family.timer.
set -euo pipefail

SRC="/mnt/pve/media/library/Family/"
DEST="/mnt/backup/Family/"
LOG="/var/log/backup-family.log"

# Refuse to run if the USB drive isn't mounted: otherwise /mnt/backup is an
# empty folder on the SSD and rsync would fill the boot disk.
if ! mountpoint -q /mnt/backup; then
  echo "$(date '+%F %T') ERROR: backup drive not mounted" >> "$LOG"
  exit 1
fi

echo "$(date '+%F %T') START" >> "$LOG"

# No --delete: files removed from the server stay on the backup.
# --modify-window=1 tolerates exFAT's coarser timestamps.
rsync -rt --modify-window=1 --exclude='.DS_Store' "$SRC" "$DEST" >> "$LOG" 2>&1
rsync -rt --modify-window=1 /mnt/pve/media/dump/ /mnt/backup/proxmox-dump/ >> "$LOG" 2>&1
rsync -rt --modify-window=1 --exclude='.DS_Store' /mnt/pve/media/library/Music/ /mnt/backup/Music/ >> "$LOG" 2>&1

echo "$(date '+%F %T') DONE" >> "$LOG"
