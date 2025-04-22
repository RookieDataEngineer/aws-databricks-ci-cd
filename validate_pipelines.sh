#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Input Validation ---
if [ -z "$1" ]; then
  echo "Error: Pipeline IDs argument is required." >&2
  echo "Usage: $0 <comma_separated_pipeline_ids> <target_environment>" >&2
  exit 1
fi

if [ -z "$2" ]; then
  echo "Error: Target environment argument is required." >&2
  echo "Usage: $0 <comma_separated_pipeline_ids> <target_environment>" >&2
  exit 1
fi

# First argument is comma-separated pipeline IDs
PIPELINE_IDS_CSV="$1"
TARGET_ENV="$2"
MAX_WAIT_SECONDS=600  # Maximum wait time (10 minutes)
POLL_INTERVAL_SECONDS=10  # How often to check status

# Convert comma-separated IDs to array
IFS=',' read -ra PIPELINE_ID_ARRAY <<< "$PIPELINE_IDS_CSV"

VALIDATION_FAILED=false
declare -a UPDATE_IDS=()
declare -a PIPELINE_MAPPING=()

# --- Trigger Validations ---
echo "Starting validation for pipelines: $PIPELINE_IDS_CSV" >&2

for pipeline_id in "${PIPELINE_ID_ARRAY[@]}"; do
  echo "Triggering validation for pipeline: $pipeline_id" >&2
  
  # Check for active updates and stop them if needed
  echo "Checking for active updates for pipeline: $pipeline_id" >&2
  
  set +e
  ACTIVE_UPDATES=$(databricks pipelines list-updates "$pipeline_id" -t "$TARGET_ENV" --output json | jq -r '.updates[] | select(.state != "COMPLETED" and .state != "FAILED" and .state != "CANCELED") | .update_id')
  set -e
  
  if [ -n "$ACTIVE_UPDATES" ]; then
    echo "Found active updates for pipeline $pipeline_id. Stopping them before validation." >&2
    for active_update in $ACTIVE_UPDATES; do
      # The correct format is 'databricks pipelines stop PIPELINE_ID'
      # The CLI may not support stopping a specific update_id
      echo "Stopping pipeline $pipeline_id" >&2
      set +e
      databricks pipelines stop "$pipeline_id" -t "$TARGET_ENV"
      set -e
      # Wait a moment to ensure the update is fully stopped
      sleep 5
    done
  fi
  
  # Now trigger the validation
  set +e
  UPDATE_JSON=$(databricks pipelines start-update "$pipeline_id" --validate-only -t "$TARGET_ENV" --output json)
  TRIGGER_RESULT=$?
  set -e
  
  if [ $TRIGGER_RESULT -eq 0 ]; then
    # Extract update ID from JSON response
    UPDATE_ID=$(echo "$UPDATE_JSON" | jq -r '.update_id')
    
    if [ -n "$UPDATE_ID" ] && [ "$UPDATE_ID" != "null" ]; then
      echo "Successfully triggered validation for pipeline $pipeline_id. Update ID: $UPDATE_ID" >&2
      UPDATE_IDS+=("$UPDATE_ID")
      PIPELINE_MAPPING+=("$pipeline_id")
    else
      echo "Failed to extract update ID from response for pipeline $pipeline_id" >&2
      VALIDATION_FAILED=true
    fi
  else
    echo "Failed to trigger validation for pipeline $pipeline_id" >&2
    VALIDATION_FAILED=true
  fi
done

# If any validations failed to trigger, exit early
if [ "$VALIDATION_FAILED" = true ]; then
  echo "failure"
  exit 0
fi

# --- Poll for Validation Results ---
echo "Polling for validation results..." >&2

start_time=$(date +%s)
all_complete=false

while [ "$all_complete" = false ]; do
  current_time=$(date +%s)
  elapsed_time=$((current_time - start_time))
  
  # Check if we've exceeded the maximum wait time
  if [ $elapsed_time -gt $MAX_WAIT_SECONDS ]; then
    echo "Exceeded maximum wait time of $MAX_WAIT_SECONDS seconds." >&2
    VALIDATION_FAILED=true
    break
  fi
  
  # Assume all complete until we find one that isn't
  all_complete=true
  
  for i in "${!UPDATE_IDS[@]}"; do
    update_id="${UPDATE_IDS[$i]}"
    pipeline_id="${PIPELINE_MAPPING[$i]}"
    
    echo "Checking status of update: $update_id for pipeline: $pipeline_id" >&2
    
    set +e
    # Use correct command format: pipelines get-update PIPELINE_ID UPDATE_ID
    STATUS_JSON=$(databricks pipelines get-update "$pipeline_id" "$update_id" -t "$TARGET_ENV" --output json)
    GET_STATUS_RESULT=$?
    set -e
    
    if [ $GET_STATUS_RESULT -eq 0 ]; then
      # Extract status from JSON response - the state is nested inside the "update" object
      UPDATE_STATE=$(echo "$STATUS_JSON" | jq -r '.update.state')
      
      echo "Update $update_id state: $UPDATE_STATE" >&2
      
      # Check if the update is still in progress
      if [[ "$UPDATE_STATE" == "IDLE" || "$UPDATE_STATE" == "CREATED" ||  "$UPDATE_STATE" == "PENDING" || "$UPDATE_STATE" == "RUNNING" || "$UPDATE_STATE" == "INITIALIZING" ]]; then
        all_complete=false
      # Check if the update failed
      elif [[ "$UPDATE_STATE" == "FAILED" || "$UPDATE_STATE" == "CANCELED" || "$UPDATE_STATE" == "TIMEDOUT" ]]; then
        echo "Validation failed for update $update_id with state $UPDATE_STATE" >&2
        VALIDATION_FAILED=true
      # Otherwise assume it succeeded (COMPLETED state)
      fi
    else
      echo "Failed to get status for update $update_id" >&2
      VALIDATION_FAILED=true
    fi
  done
  
  # If not all complete, wait before polling again
  if [ "$all_complete" = false ] && [ "$VALIDATION_FAILED" = false ]; then
    echo "Not all validations complete. Waiting $POLL_INTERVAL_SECONDS seconds before next poll..." >&2
    sleep $POLL_INTERVAL_SECONDS
  fi
done

if [ "$VALIDATION_FAILED" = true ]; then
  echo "failure"
  # Exit with non-zero status to signal failure to GitHub Actions
  exit 1
else
  echo "success"
  exit 0
fi