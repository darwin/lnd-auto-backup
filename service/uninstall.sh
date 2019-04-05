#!/usr/bin/env bash

set -e -o pipefail

TARGET="/etc/systemd/system/lnd-auto-backup.service"

set -x
sudo systemctl stop lnd-auto-backup.service
sudo rm ${TARGET}