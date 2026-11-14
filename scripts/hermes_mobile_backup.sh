#!/usr/bin/env bash
# Encrypted local backup of the Hermes mobile-push companion state.
# Includes outbox/inbox SQLite (online backup API), operator policy and the VAPID private key.
# Output stays on this Mac (~/HermesBackups); the passphrase lives in the macOS Keychain
# (service "hermes-mobile-push-backup"). Nothing is uploaded and no secret is printed.
#
#   scripts/hermes_mobile_backup.sh            create + verify a backup
#   scripts/hermes_mobile_backup.sh --verify F restore F to a temp dir and check integrity only
set -euo pipefail

HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
DATA="$HOME_DIR/plugin-data/mobile-push"
DEST="${HERMES_MOBILE_BACKUP_DIR:-$HOME/HermesBackups}"
SERVICE="hermes-mobile-push-backup"

passphrase() { security find-generic-password -a "$USER" -s "$SERVICE" -w; }

verify() {
  local file="$1" tmp
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass "pass:$(passphrase)" -in "$file" | tar -C "$tmp" -xzf -
  for db in outbox inbox; do
    [ "$(sqlite3 "$tmp/mobile-push/$db.sqlite3" 'pragma integrity_check')" = ok ] || { echo "verify=failed db=$db"; return 1; }
  done
  cmp -s "$DATA/vapid-private.pem" "$tmp/mobile-push/vapid-private.pem" || echo "note=vapid_differs_from_live"
  echo "verify=ok registrations=$(sqlite3 "$tmp/mobile-push/outbox.sqlite3" 'select count(*) from registrations')"
}

if [ "${1:-}" = "--verify" ]; then verify "${2:?backup file required}"; exit; fi

[ -d "$DATA" ] || { echo "backup=failed reason=no_mobile_push_data"; exit 1; }
mkdir -p "$DEST"; chmod 700 "$DEST"
if ! security find-generic-password -a "$USER" -s "$SERVICE" >/dev/null 2>&1; then
  security add-generic-password -a "$USER" -s "$SERVICE" -w "$(openssl rand -base64 32)"
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/mobile-push"
for db in outbox inbox; do
  python3 - "$DATA/$db.sqlite3" "$work/mobile-push/$db.sqlite3" <<'PY'
import sqlite3, sys
src = sqlite3.connect(sys.argv[1], timeout=10)
dst = sqlite3.connect(sys.argv[2])
src.backup(dst)
dst.close(); src.close()
PY
done
cp -p "$DATA/config.json" "$DATA/vapid-private.pem" "$work/mobile-push/"

out="$DEST/mobile-push-$(date +%Y%m%d-%H%M%S).tgz.enc"
tar -C "$work" -czf - mobile-push | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -pass "pass:$(passphrase)" -out "$out"
chmod 600 "$out"
verify "$out"
echo "backup=$out"
