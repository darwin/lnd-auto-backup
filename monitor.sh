#!/usr/bin/env bash

set -e -o pipefail

LAUNCH_DIR=$(pwd -P)

cd "$(dirname "${BASH_SOURCE[0]}")"

ROOT_DIR="$(pwd -P)"

LND_AUTO_BACKUP_LAUNCHED_BY_SYSTEMD=${LND_AUTO_BACKUP_LAUNCHED_BY_SYSTEMD}
if [[ -n "$LND_AUTO_BACKUP_LAUNCHED_BY_SYSTEMD" ]]; then
  echo "sourcing '$ROOT_DIR/.envrc' because being launched as a systemd service..."
  . ./.envrc
fi

LND_HOME=${LND_HOME:-$HOME/.lnd}
LND_NETWORK=${LND_NETWORK:-mainnet}
LND_CHAIN=${LND_CHAIN:-bitcoin}
LND_BACKUP_SCRIPT=${LND_BACKUP_SCRIPT:-$ROOT_DIR/backup-via-s3.sh}
LND_CHANNEL_BACKUP_PATH=${LND_CHANNEL_BACKUP_PATH:-"$LND_HOME/data/chain/$LND_CHAIN/$LND_NETWORK/channel.backup"}

if [[ ! -e "$LND_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LND_BACKUP_SCRIPT'"
  exit 1
fi

# ---------------------------------------------------------------------------------------------------------------------------

trigger_backup() {
  local backup_label=$1
  local file=$2
  ${LND_BACKUP_SCRIPT} ${backup_label} "$(realpath ${file})"
}

backup_label() {
  local stamp=$(date -d "today" +"%Y%m%d_%H%M_%S")
  echo "${LND_CHAIN}_${LND_NETWORK}_${stamp}_channel.backup"
}

# ---------------------------------------------------------------------------------------------------------------------------

function finish {
  echo "finished monitoring '$LND_CHANNEL_BACKUP_PATH'"
}
trap finish EXIT

echo
echo "======================================================================================================================="
echo
echo "monitoring '$LND_CHANNEL_BACKUP_PATH'"

if [[ ! -e "$LND_CHANNEL_BACKUP_PATH" ]]; then
  echo "waiting for '$LND_CHANNEL_BACKUP_PATH' to be created..."
  until [[ -e "$LND_CHANNEL_BACKUP_PATH" ]]; do
    sleep 1
  done
  trigger_backup "$(backup_label)" ${LND_CHANNEL_BACKUP_PATH}
fi

while inotifywait -e close_write "$LND_CHANNEL_BACKUP_PATH"; do
  trigger_backup "$(backup_label)" ${LND_CHANNEL_BACKUP_PATH}
done

