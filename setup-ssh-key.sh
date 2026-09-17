#!/bin/bash
# One-time setup: generate an SSH keypair for the backup upload and pin the
# sftpgo host key, so the main script never needs a password and never
# blindly trusts whatever host key shows up (that's what "Host key
# verification failed" was actually protecting you from after the rebuild).
set -euo pipefail

CURRENTDIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
ENV_FILE="$CURRENTDIR/mailcow-backup.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE — copy mailcow-backup.env.example to mailcow-backup.env and edit it first." >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

: "${SFTP_HOST:?SFTP_HOST not set in mailcow-backup.env}"
: "${SFTP_PORT:?SFTP_PORT not set in mailcow-backup.env}"
: "${SFTP_SSH_KEY_FILE:?SFTP_SSH_KEY_FILE not set in mailcow-backup.env}"
: "${SFTP_KNOWN_HOSTS_FILE:?SFTP_KNOWN_HOSTS_FILE not set in mailcow-backup.env}"

mkdir -p "$(dirname "$SFTP_SSH_KEY_FILE")"
chmod 700 "$(dirname "$SFTP_SSH_KEY_FILE")"

if [[ -f "$SFTP_SSH_KEY_FILE" ]]; then
    echo "Key already exists at $SFTP_SSH_KEY_FILE — leaving it alone."
else
    echo "Generating ed25519 keypair (no passphrase — this runs unattended from cron)..."
    ssh-keygen -t ed25519 -N "" -C "mailcow-backup@$(hostname)" -f "$SFTP_SSH_KEY_FILE"
    chmod 600 "$SFTP_SSH_KEY_FILE"
    chmod 644 "$SFTP_SSH_KEY_FILE.pub"
fi

echo
echo "Scanning host key for $SFTP_HOST:$SFTP_PORT ..."
SCANNED_KEY=$(ssh-keyscan -p "$SFTP_PORT" -t ed25519,rsa,ecdsa "$SFTP_HOST" 2>/dev/null | grep -v '^#' || true)

if [[ -z "$SCANNED_KEY" ]]; then
    echo "Could not reach $SFTP_HOST:$SFTP_PORT to scan its host key. Check the host/port and try again." >&2
    exit 1
fi

echo "$SCANNED_KEY"
echo
echo "!! Verify this matches the sftpgo server's actual host key fingerprint"
echo "!! (e.g. run 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' on the sftpgo box itself)."
echo "!! This is the ONLY point where a man-in-the-middle could slip in a fake key — check it now."
read -r -p "Type 'yes' once you've verified it: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted — not pinning an unverified host key." >&2
    exit 1
fi

echo "$SCANNED_KEY" > "$SFTP_KNOWN_HOSTS_FILE"
chmod 600 "$SFTP_KNOWN_HOSTS_FILE"
echo "Pinned host key written to $SFTP_KNOWN_HOSTS_FILE"

echo
echo "=========================================================================="
echo "Add this PUBLIC key to the sftpgo user '$SFTP_USER' (Web Admin -> Users ->"
echo "$SFTP_USER -> Public keys), then run mailcow-backup.sh."
echo "=========================================================================="
cat "$SFTP_SSH_KEY_FILE.pub"
