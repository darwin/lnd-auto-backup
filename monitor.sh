#!/usr/bin/env bash

set -e -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

ROOT_DIR="$(pwd -P)"

LNDAB_LAUNCHED_BY_SYSTEMD=${LNDAB_LAUNCHED_BY_SYSTEMD}
if [[ -n "$LNDAB_LAUNCHED_BY_SYSTEMD" ]]; then
  echo "sourcing '$ROOT_DIR/.envrc' because being launched as a systemd service..."
  . ./.envrc
fi

LND_HOME=${LND_HOME:-$HOME/.lnd}
LND_NETWORK=${LND_NETWORK:-mainnet}
LND_CHAIN=${LND_CHAIN:-bitcoin}
LNDAB_CHANNEL_BACKUP_PATH=${LNDAB_CHANNEL_BACKUP_PATH:-"$LND_HOME/data/chain/$LND_CHAIN/$LND_NETWORK/channel.backup"}
LNDAB_BACKUP_SCRIPT=${LNDAB_BACKUP_SCRIPT:-$ROOT_DIR/backup-via-s3.sh}

if [[ ! -e "$LNDAB_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LNDAB_BACKUP_SCRIPT'"
  exit 1
fi

# ---------------------------------------------------------------------------------------------------------------------------

backup_label() {
  local stamp=$(date -d "today" +"%Y%m%d_%H%M_%S")
  echo "${LND_CHAIN}_${LND_NETWORK}_${stamp}_channel.backup"
}

perform_backup() {
  ${LNDAB_BACKUP_SCRIPT} "$(backup_label)" ${LNDAB_CHANNEL_BACKUP_PATH}
}

# ---------------------------------------------------------------------------------------------------------------------------

function finish {
  echo "finished monitoring '$LNDAB_CHANNEL_BACKUP_PATH'"
}
trap finish EXIT

echo
echo "======================================================================================================================="
echo
echo "monitoring '$LNDAB_CHANNEL_BACKUP_PATH'"

if [[ ! -e "$LNDAB_CHANNEL_BACKUP_PATH" ]]; then
  echo "waiting for '$LNDAB_CHANNEL_BACKUP_PATH' to be created..."
  until [[ -e "$LNDAB_CHANNEL_BACKUP_PATH" ]]; do
    sleep 1
  done
  perform_backup
fi

while inotifywait -e close_write "$LNDAB_CHANNEL_BACKUP_PATH"; do
  perform_backup
done