#!/usr/bin/env bash

set -e -o pipefail

LAB_S3_BUCKET=${LAB_S3_BUCKET:?required}

LABEL=${1:?required}
FILE=${2:?required}

set -x
exec aws s3 cp "$FILE" "s3://$LAB_S3_BUCKET/$LABEL"