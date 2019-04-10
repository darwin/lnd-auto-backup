#!/usr/bin/env bash

set -e -o pipefail

LNDAB_RSYNC_TARGET=${LNDAB_RSYNC_TARGET:?required}
LNDAB_RSYNC_OPTS=${LNDAB_RSYNC_OPTS:-"-av"}

LABEL=${1:?required}
FILE=${2:?required}

set -x
exec rsync ${LNDAB_RSYNC_OPTS} "$FILE" "$LNDAB_RSYNC_TARGET/$LABEL"