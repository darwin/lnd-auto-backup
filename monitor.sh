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
LNDAB_VERBOSE=${LNDAB_VERBOSE}
LNDAB_CHANNEL_BACKUP_PATH=${LNDAB_CHANNEL_BACKUP_PATH:-"$LND_HOME/data/chain/$LND_CHAIN/$LND_NETWORK/channel.backup"}
LNDAB_FILE_CREATION_POLLING_TIME=${LNDAB_FILE_CREATION_POLLING_TIME:-1}
LNDAB_INOTIFYWAIT_OPTS=${LNDAB_INOTIFYWAIT_OPTS:-"-q"}

LNDAB_S3_BUCKET=${LNDAB_S3_BUCKET}
LNDAB_S3_BACKUP_SCRIPT=${LNDAB_S3_BACKUP_SCRIPT:-$ROOT_DIR/backup-via-s3.sh}

LNDAB_RSYNC_TARGET=${LNDAB_RSYNC_TARGET}
LNDAB_RSYNC_BACKUP_SCRIPT=${LNDAB_RSYNC_BACKUP_SCRIPT:-$ROOT_DIR/backup-via-rsync.sh}

LNDAB_CUSTOM_BACKUP_SCRIPT=${LNDAB_CUSTOM_BACKUP_SCRIPT}

LNDAB_NOERR=0
LNDAB_BACKUP_SCRIPT_NOT_FOUND=10

if [[ -n "$LNDAB_S3_BUCKET" && ! -e "$LNDAB_S3_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LNDAB_S3_BACKUP_SCRIPT', check LNDAB_S3_BACKUP_SCRIPT"
  exit ${LNDAB_BACKUP_SCRIPT_NOT_FOUND}
fi

if [[ -n "$LNDAB_RSYNC_TARGET" && ! -e "$LNDAB_RSYNC_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LNDAB_RSYNC_BACKUP_SCRIPT', check LNDAB_RSYNC_BACKUP_SCRIPT"
  exit ${LNDAB_BACKUP_SCRIPT_NOT_FOUND}
fi

if [[ -n "$LNDAB_CUSTOM_BACKUP_SCRIPT" && ! -e "$LNDAB_CUSTOM_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LNDAB_CUSTOM_BACKUP_SCRIPT', check LNDAB_CUSTOM_BACKUP_SCRIPT"
  exit ${LNDAB_BACKUP_SCRIPT_NOT_FOUND}
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
  local stamp=$(date -d "today" +"%Y%m%d_%H%M_%S")
  echo "${LND_CHAIN}_${LND_NETWORK}_${stamp}_channel.backup"
}

perform_backup() {
  local new_label=$(generate_backup_label)
  if [[ -n "$LNDAB_S3_BUCKET" ]]; then
    notify STATUS="performing backup of '$LNDAB_CHANNEL_BACKUP_PATH' as '$new_label' using '$LNDAB_S3_BACKUP_SCRIPT'"
    ${LNDAB_S3_BACKUP_SCRIPT} "$new_label" ${LNDAB_CHANNEL_BACKUP_PATH}
  fi
  if [[ -n "$LNDAB_RSYNC_TARGET" ]]; then
    notify STATUS="performing backup of '$LNDAB_CHANNEL_BACKUP_PATH' as '$new_label' using '$LNDAB_RSYNC_BACKUP_SCRIPT'"
    ${LNDAB_RSYNC_BACKUP_SCRIPT} "$new_label" ${LNDAB_CHANNEL_BACKUP_PATH}
  fi
  if [[ -n "$LNDAB_CUSTOM_BACKUP_SCRIPT" ]]; then
    notify STATUS="performing backup of '$LNDAB_CHANNEL_BACKUP_PATH' as '$new_label' using '$LNDAB_CUSTOM_BACKUP_SCRIPT'"
    ${LNDAB_CUSTOM_BACKUP_SCRIPT} "$new_label" ${LNDAB_CHANNEL_BACKUP_PATH}
  fi
}

do_missing_channel_backup_workflow() {
  echo "waiting for '$LNDAB_CHANNEL_BACKUP_PATH' to be created..."
  wait_for_creation
  perform_backup
}

start_monitoring_changes() {
  notify STATUS="waiting for changes in '$LNDAB_CHANNEL_BACKUP_PATH'"

  # The idea is to continuously monitor channel.backup via inotifywait and decide what to do by analyzing the output.

  # Originally, I let inotifywait wait just for 'CLOSE_WRITE' event and then perform backup on zero exit status code.
  # It worked, but the issue was that after lnd wallet unlocking lnd touches the file and triggers unexpected 'ATTRIB' event,
  # this caused inotifywait to return error status code and in turn this script exited with error and
  # the whole service got unexpectedly restarted.

  # In reality lnd triggers ATTRIB event followed by DELETE_SELF event, but immediately re-creates the file.
  # But that file creation is not reflected by inotifywait because it loses track of the file (inotifywait would have to be
  # executed again to setup proper monitors for new file). At least this is observed behaviour on my Ubuntu 18.10 host machine
  # running lnd in a docker container with lnd data directory mapped to host.
  # This script tries to be robust and handle this case properly, on DELETE_SELF it breaks from start_monitoring_changes
  # but enters it again via next main loop iteration. You can spot it in logs by seeing 'waiting for changes in ...'
  # reported again.

  echo "waiting for changes in '$LNDAB_CHANNEL_BACKUP_PATH'"
  local events
  while read events; do
    local backup_needed=
    local deleted_self=

    # inspect $events, which is a comma-delimited list of events, e.g. CLOSE_NOWRITE,CLOSE
    for event in ${events//,/ }; do
      case "$event" in
        CLOSE_WRITE) backup_needed=1 ;;
        DELETE_SELF) deleted_self=1 ;;
      esac
    done

    if [[ -n "$deleted_self" ]]; then
      if [[ -n "$LNDAB_VERBOSE" ]]; then
        echo "inotifywait reported event(s) ${events} which suggest unexpected file deletion"
      fi
      # as noted above, the file can be already re-created at this point, we report deletion only in persistent cases
      if [[ ! -e "$LNDAB_CHANNEL_BACKUP_PATH" ]]; then
        echo "monitored file '$LNDAB_CHANNEL_BACKUP_PATH' was unexpectedly deleted"
      fi
      break;
    fi

    if [[ -z "$backup_needed" ]]; then
      if [[ -n "$LNDAB_VERBOSE" ]]; then
        echo "inotifywait reported event(s) ${events} which won't trigger a new backup"
      fi
    else
      if [[ -n "$LNDAB_VERBOSE" ]]; then
        echo "inotifywait reported event(s) ${events} which will trigger a new backup"
      fi
      perform_backup
    fi
  done < <(nohup inotifywait ${LNDAB_INOTIFYWAIT_OPTS} -m --format '%e' "$LNDAB_CHANNEL_BACKUP_PATH")
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
    do_missing_channel_backup_workflow
  fi

  start_monitoring_changes
done