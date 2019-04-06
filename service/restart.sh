#!/usr/bin/env bash

set -e -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

exec ./control.sh restart