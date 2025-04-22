#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status.
set -e
# --- Input Validation ---
if [ -z "$1" ]; then
  echo "Error: Target environment argument is required." >&2
  echo "Usage: $0 <target_environment>" >&2
  exit 1
fi
TARGET_ENV="$1"
# --- Main Logic ---
echo "Fetching pipeline IDs managed by the bundle for target: $TARGET_ENV using 'bundle summary'..." >&2
# Execute command pipeline. If it fails (non-zero exit), set -e will cause script to exit.
PIPELINE_IDS=$(databricks bundle summary -t "$TARGET_ENV" --output json | jq -r '.resources.pipelines[].id')
# Check if PIPELINE_IDS is empty (can happen if no pipelines or jq path yields nothing)
if [ -z "$PIPELINE_IDS" ]; then
  echo "Warning: No DLT pipelines found in the summary for target '$TARGET_ENV'." >&2
  # Output empty string to stdout and exit successfully
  echo ""
  exit 0
fi
echo "Found Pipeline IDs (raw):" >&2
echo "$PIPELINE_IDS" >&2 # Log raw IDs to stderr for debugging
# Format IDs as a comma-separated string for easier iteration in bash
IDS_ONELINE=$(echo "$PIPELINE_IDS" | tr '\n' ',' | sed 's/,$//')  # Replace newlines with commas and trim trailing comma
echo "Formatted IDs: $IDS_ONELINE" >&2 # Log formatted IDs to stderr
# --- Output ---
# Print ONLY the final formatted string to stdout for capture
echo "$IDS_ONELINE"
exit 0