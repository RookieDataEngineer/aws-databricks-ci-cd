#!/usr/bin/env bash
# update_bundle_host.sh
#
# This script accepts a Databricks host URL as an argument
# and replaces DATABRICKS_HOST_PLACEHOLDER in databricks.yml.
# It hard-codes the value so subsequent commands see the real host.

set -euo pipefail

# Check if an argument is provided
if [ $# -lt 1 ]; then
  echo "Error: Missing Databricks host URL argument."
  echo "Usage: $0 <databricks-host-url>"
  exit 1
fi

# Get the Databricks host URL from the first argument
HOST_URL="$1"

# Path to your bundle file
BUNDLE_FILE="databricks.yml"

# Check if the bundle file exists
if [ ! -f "$BUNDLE_FILE" ]; then
  echo "Error: Bundle file '$BUNDLE_FILE' not found."
  exit 1
fi

# Create a backup (databricks.yml.bak) and replace the placeholder
sed -i.bak "s|DATABRICKS_HOST_PLACEHOLDER|$HOST_URL|g" "$BUNDLE_FILE"

echo "Replaced DATABRICKS_HOST_PLACEHOLDER with $HOST_URL in $BUNDLE_FILE"