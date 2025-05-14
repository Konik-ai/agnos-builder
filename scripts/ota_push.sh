#!/usr/bin/env bash
set -e

# Make sure we're in the correct directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd $DIR

# Constants
OTA_DIR="$DIR/../output/ota"
DATA_ACCOUNT="comma"

OTA_JSON="$OTA_DIR/agnos.json"
DATA_CONTAINER="agnosupdate"
VERSION=$(< $DIR/../VERSION)

# Liftoff!
echo "Copying output/ota to r2:$DATA_ACCOUNT/$DATA_CONTAINER/$VERSION..."
rclone sync -P "$OTA_DIR" "r2:$DATA_ACCOUNT/$DATA_CONTAINER/$VERSION"
# rclone copy -P "$OTA_DIR" "r2:$DATA_ACCOUNT/$DATA_CONTAINER/$VERSION"
# rclone copy -P "$OTA_DIR" --include "*.img.xz" "r2:$DATA_ACCOUNT/$DATA_CONTAINER/$VERSION"

echo "Done!"
