#!/usr/bin/env bash

# see https://gist.github.com/alexbosworth/2c5e185aedbdac45a03655b709e255a3

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
LNDAB_VERBOSE=${LNDAB_VERBOSE}
LNDAB_CHANNEL_BACKUP_PATH=${LNDAB_CHANNEL_BACKUP_PATH:-"$LND_HOME/data/chain/$LND_CHAIN/$LND_NETWORK/channel.backup"}
LNDAB_FILE_CREATION_POLLING_TIME=${LNDAB_FILE_CREATION_POLLING_TIME:-1}
LNDAB_INOTIFYWAIT_OPTS=${LNDAB_INOTIFYWAIT_OPTS:-"-q"}
LNDAB_CHECKSUM_FILE=${LNDAB_CHECKSUM_FILE:-.last_backup_checksum}

LNDAB_S3_BUCKET=${LNDAB_S3_BUCKET}
LNDAB_S3_BACKUP_SCRIPT=${LNDAB_S3_BACKUP_SCRIPT:-$ROOT_DIR/backup-via-s3.sh}

LNDAB_RSYNC_TARGET=${LNDAB_RSYNC_TARGET}
LNDAB_RSYNC_BACKUP_SCRIPT=${LNDAB_RSYNC_BACKUP_SCRIPT:-$ROOT_DIR/backup-via-rsync.sh}

LNDAB_CUSTOM_BACKUP_SCRIPT=${LNDAB_CUSTOM_BACKUP_SCRIPT}

LNDAB_ERR_BACKUP_SCRIPT_NOT_FOUND=10
LNDAB_ERR_SHA1SUM_NOT_AVAIL=11

if [[ -n "$LNDAB_S3_BUCKET" && ! -e "$LNDAB_S3_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LNDAB_S3_BACKUP_SCRIPT', check LNDAB_S3_BACKUP_SCRIPT"
  exit ${LNDAB_ERR_BACKUP_SCRIPT_NOT_FOUND}
fi

if [[ -n "$LNDAB_RSYNC_TARGET" && ! -e "$LNDAB_RSYNC_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LNDAB_RSYNC_BACKUP_SCRIPT', check LNDAB_RSYNC_BACKUP_SCRIPT"
  exit ${LNDAB_ERR_BACKUP_SCRIPT_NOT_FOUND}
fi

if [[ -n "$LNDAB_CUSTOM_BACKUP_SCRIPT" && ! -e "$LNDAB_CUSTOM_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LNDAB_CUSTOM_BACKUP_SCRIPT', check LNDAB_CUSTOM_BACKUP_SCRIPT"
  exit ${LNDAB_ERR_BACKUP_SCRIPT_NOT_FOUND}
fi

if ! hash sha1sum 2>/dev/null; then
  echo "sha1sum not available on your system, please install it"
  exit ${LNDAB_ERR_SHA1SUM_NOT_AVAIL}
fi

# ---------------------------------------------------------------------------------------------------------------------------

notify() {
  if [[ -n "$LNDAB_LAUNCHED_BY_SYSTEMD" ]]; then
    systemd-notify "$@"
  fi
}

wait_for_creation() {
  notify STATUS="waiting for creation of '$LNDAB_CHANNEL_BACKUP_PATH'"
  until [[ -e "$LNDAB_CHANNEL_BACKUP_PATH" ]]; do
    sleep ${LNDAB_FILE_CREATION_POLLING_TIME}
  done
}

generate_backup_label() {
  local stamp
  stamp=$(date -d "today" +"%Y%m%d_%H%M_%S")
  echo "${LND_CHAIN}_${LND_NETWORK}_${stamp}_channel.backup"
}

write_backup_sha() {
  sha1sum --binary "$LNDAB_CHANNEL_BACKUP_PATH" > "$LNDAB_CHECKSUM_FILE"
}

check_backup_sha() {
  sha1sum --status --check "$LNDAB_CHECKSUM_FILE"
}

perform_backup() {
  local new_label
  new_label=$(generate_backup_label)
  write_backup_sha
  if [[ -n "$LNDAB_S3_BUCKET" ]]; then
    notify STATUS="performing backup of '$LNDAB_CHANNEL_BACKUP_PATH' as '$new_label' using '$LNDAB_S3_BACKUP_SCRIPT'"
    ${LNDAB_S3_BACKUP_SCRIPT} "$new_label" "${LNDAB_CHANNEL_BACKUP_PATH}"
  fi
  if [[ -n "$LNDAB_RSYNC_TARGET" ]]; then
    notify STATUS="performing backup of '$LNDAB_CHANNEL_BACKUP_PATH' as '$new_label' using '$LNDAB_RSYNC_BACKUP_SCRIPT'"
    ${LNDAB_RSYNC_BACKUP_SCRIPT} "$new_label" "${LNDAB_CHANNEL_BACKUP_PATH}"
  fi
  if [[ -n "$LNDAB_CUSTOM_BACKUP_SCRIPT" ]]; then
    notify STATUS="performing backup of '$LNDAB_CHANNEL_BACKUP_PATH' as '$new_label' using '$LNDAB_CUSTOM_BACKUP_SCRIPT'"
    ${LNDAB_CUSTOM_BACKUP_SCRIPT} "$new_label" "${LNDAB_CHANNEL_BACKUP_PATH}"
  fi
}

perform_backup_if_needed() {
  # we perform backup only if sha differs
  if ! check_backup_sha; then
    perform_backup
  else
    if [[ -n "$LNDAB_VERBOSE" ]]; then
      echo "perform_backup_if_needed called, but checksum was the same => skipped the backup"
    fi
  fi
}

# ---------------------------------------------------------------------------------------------------------------------------

function finish {
  echo "finished monitoring '$LNDAB_CHANNEL_BACKUP_PATH'"
}
trap finish EXIT

notify READY=1

echo
echo "======================================================================================================================="
echo
echo "monitoring '$LNDAB_CHANNEL_BACKUP_PATH'"

while true; do
  if [[ ! -e "$LNDAB_CHANNEL_BACKUP_PATH" ]]; then
    echo "waiting for '$LNDAB_CHANNEL_BACKUP_PATH' to be created..."
    wait_for_creation
  fi

  sleep ${LNDAB_FILE_CREATION_POLLING_TIME}
  perform_backup_if_needed

  echo "waiting for changes in '$LNDAB_CHANNEL_BACKUP_PATH'"
  set +e
  inotifywait ${LNDAB_INOTIFYWAIT_OPTS} "$LNDAB_CHANNEL_BACKUP_PATH"
  set -e
done