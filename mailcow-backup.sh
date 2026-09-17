#!/bin/bash
# Runs mailcow's own backup script, then mirrors the result to sftpgo over
# SFTP using an SSH key (no password on disk or on the command line) with a
# pinned host key (see setup-ssh-key.sh). Run once via setup-ssh-key.sh
# before the first real run.
set -euo pipefail

CURRENTDIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
ENV_FILE="$CURRENTDIR/mailcow-backup.env"
LOGFILE="$CURRENTDIR/logs/$(date '+%Y-%m-%d')_mailcow-backup"

mkdir -p "$CURRENTDIR/logs"
source "$CURRENTDIR/functions.inc"

if [[ ! -f "$ENV_FILE" ]]; then
    log_write "Missing $ENV_FILE — copy mailcow-backup.env.example to mailcow-backup.env and edit it." e
    exit 2
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

require_var SFTP_HOST SFTP_PORT SFTP_USER SFTP_TARGET_DIR SFTP_SSH_KEY_FILE \
            SFTP_KNOWN_HOSTS_FILE MAILCOW_SCRIPT MAILCOW_BACKUP_LOCATION \
            BACKUP_RETENTION_DAYS
require_cmd rclone flock

# Prevent two runs from overlapping (e.g. a slow backup still running when
# cron fires again).
LOCKFILE="$CURRENTDIR/.mailcow-backup.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    log_write "Another run is already in progress (lock: $LOCKFILE). Exiting." e
    exit 1
fi

if [[ ! -f "$SFTP_SSH_KEY_FILE" || ! -f "$SFTP_KNOWN_HOSTS_FILE" ]]; then
    log_write "SSH key or pinned known_hosts file missing. Run ./setup-ssh-key.sh first." e
    exit 2
fi

# Prune old local logs so this doesn't grow forever.
find "$CURRENTDIR/logs" -name '*_mailcow-backup.log' -mtime "+${LOG_RETENTION_DAYS:-30}" -delete

log_write "=== Starting mailcow backup ==="
if ! "$MAILCOW_SCRIPT" backup all --delete-days "$BACKUP_RETENTION_DAYS" 2>&1 | tee -a "$LOGFILE.log"; then
    log_write "mailcow backup script failed — aborting before touching the remote copy." e
    exit 1
fi

if [[ ! -d "$MAILCOW_BACKUP_LOCATION" ]] || [[ -z "$(ls -A "$MAILCOW_BACKUP_LOCATION" 2>/dev/null)" ]]; then
    log_write "$MAILCOW_BACKUP_LOCATION is missing or empty after the backup ran — aborting before mirroring (this would otherwise wipe the remote copy)." e
    exit 1
fi

log_write "=== Uploading to sftpgo ($SFTP_HOST:$SFTP_PORT) ==="
# On-the-fly rclone remote — no rclone.conf, no secret on disk beyond the
# SSH private key itself. known_hosts_file makes rclone actually verify the
# host key instead of trusting whatever key the server happens to present.
REMOTE=":sftp,host=${SFTP_HOST},port=${SFTP_PORT},user=${SFTP_USER},key_file=${SFTP_SSH_KEY_FILE},known_hosts_file=${SFTP_KNOWN_HOSTS_FILE}:${SFTP_TARGET_DIR}"

if rclone sync "$MAILCOW_BACKUP_LOCATION" "$REMOTE" \
    --log-file "$LOGFILE.log" --log-level INFO \
    --retries 3 --low-level-retries 10 --transfers 4; then
    log_write "=== Backup and upload finished successfully ==="
else
    log_write "rclone sync failed — local backup is fine, but it did not reach sftpgo. Check $LOGFILE.log." e
    exit 1
fi
