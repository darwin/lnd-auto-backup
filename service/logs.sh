#!/usr/bin/env bash

set -x
sudo journalctl -u lnd-auto-backup.service -f -n 500