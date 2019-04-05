#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE[0]}")"

CMD=${1:-status}

set -x
exec sudo systemctl ${CMD} lnd-auto-backup.service
