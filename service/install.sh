#!/usr/bin/env bash

set -e -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

SERVICE_DIR="$(pwd -P)"

TARGET="/etc/systemd/system/lnd-auto-backup.service"
SOURCE="$SERVICE_DIR/lnd-auto-backup.service"

set -x
sudo cp ${SOURCE} ${TARGET}

sudo chmod 755 /etc/systemd/system/lnd-auto-backup.service
sudo systemctl daemon-reload
