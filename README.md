# mailcow-backup

Runs mailcow's `backup_and_restore.sh`, then mirrors the result to an
sftpgo server over SFTP.

## What changed from the old version

- **No password anywhere.** Upload now authenticates with an SSH keypair
  instead of a password sitting in plaintext in the script (and visible to
  anyone on the box running `ps`).
- **Host key is actually checked.** The old `Host key verification failed`
  error was lftp correctly refusing to trust an unrecognized host key after
  the rebuild. This version pins the sftpgo host key once (`setup-ssh-key.sh`)
  and verifies against it every run, instead of disabling the check.
- **lftp → rclone.** Actively maintained, single static binary, proper
  `sync` (mirror + delete) support, and real host-key pinning
  (`known_hosts_file`) rather than lftp's SFTP-over-SSH quirks.
- **Won't wipe the remote on a bad local backup.** If mailcow's backup step
  fails, or the local backup directory ends up empty, the script aborts
  before running `rclone sync` — a mirror-with-delete against an empty or
  broken source would otherwise delete every good backup on sftpgo too.
- **Config and secrets out of the script.** Host/user/paths live in
  `mailcow-backup.env` (git-ignored); the script itself has nothing
  environment-specific in it.
- **Lockfile** so an overlapping cron run can't step on one still in
  progress.

## Setup

1. Install rclone on the mailcow host (static binary, no distro package
   needed): `curl https://rclone.org/install.sh | sudo bash`
2. `cp mailcow-backup.env.example mailcow-backup.env` and edit it for this
   host (hostname/IP, port, mailcow paths, retention).
3. `./setup-ssh-key.sh` — generates an SSH keypair, scans and pins the
   sftpgo host key (you'll be asked to confirm the fingerprint — verify it
   against the sftpgo box itself, e.g. `ssh-keygen -lf
   /etc/ssh/ssh_host_ed25519_key.pub`), and prints the public key.
4. In sftpgo's admin UI, add the printed public key to the
   `mailcow-backup` user (Users → mailcow-backup → Public keys).
5. Run `./mailcow-backup.sh` by hand once to confirm it works end-to-end,
   then wire it into cron as before.

## Files

| File | Committed? | Purpose |
|---|---|---|
| `mailcow-backup.sh` | yes | main script |
| `functions.inc` | yes | logging + validation helpers |
| `setup-ssh-key.sh` | yes | one-time key generation + host-key pinning |
| `mailcow-backup.env.example` | yes | config template |
| `mailcow-backup.env` | **no** | this host's actual config |
| `.ssh/` | **no** | generated private key + pinned known_hosts |
| `logs/` | no (dir only) | daily run logs, auto-pruned after `LOG_RETENTION_DAYS` |
| `backups/` | no (dir only) | mailcow's local backup output |

## If the sftpgo host key ever legitimately changes

(e.g. you rebuild the sftpgo box) re-run `./setup-ssh-key.sh` — it leaves an
existing keypair alone but will re-scan and let you re-pin the host key
after you verify the new fingerprint.
