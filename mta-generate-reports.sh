#!/bin/bash

# Avoid tee overwriting error code 
set -o pipefail

MTA_ARTIFACT_LIST_FILE="${1:-$MTA_ARTIFACT_LIST_FILE}"
MTA_REPORTS_OUTPUT_DIR="${2:-$MTA_REPORTS_OUTPUT_DIR}"
MTA_ARTIFACT_DONE_FILE="${MTA_ARTIFACT_DONE_FILE:-$MTA_REPORTS_OUTPUT_DIR/artifacts.done}"
MTA_RUN_LOG_FILE="${MTA_RUN_LOG_FILE:-$MTA_REPORTS_OUTPUT_DIR/report.log}"

NEXUS_USERNAME="${NEXUS_USERNAME:-$myusername}"
NEXUS_PASSWORD="${NEXUS_PASSWORD:-$mypassword}"

# Check parameters
if [ -z "$MTA_HOME" -o ! -f "$MTA_HOME/bin/mta-cli" ]; then
    echo "MTA_HOME is required. E.g. 'export MTA_HOME=/home/myuser/mta-cli-5.1.0.Final'"
    exit 1
fi

if [ -z "$MTA_ARTIFACT_LIST_FILE" -o -z "$MTA_REPORTS_OUTPUT_DIR" ]; then
    echo "Usage: ./mta-generate-rerports.sh [MTA_ARTIFACT_LIST_FILE] [MTA_REPORTS_OUTPUT_DIR]
    The MTA_ARTIFACT_LIST_FILE input file is expected to contain the list of artifacts to scan, one per each line. 
    The MTA_REPORTS_OUTPUT_DIR output directory is where the reports will be created."
    exit 1 
fi

mkdir -p "$MTA_REPORTS_OUTPUT_DIR" || { echo "Failed to create MTA_REPORTS_OUTPUT_DIR=$MTA_REPORTS_OUTPUT_DIR"; exit 1; }
touch "$MTA_ARTIFACT_DONE_FILE" || { echo "Can't write file MTA_ARTIFACT_DONE_FILE=$MTA_ARTIFACT_DONE_FILE"; exit 1; }


# Loop over artifact list
cat "$MTA_ARTIFACT_LIST_FILE" | while read -r ARTIFACT_INFO
do
    # Download url
    ARTIFACT=$( echo $ARTIFACT_INFO | awk -F, '{ gsub(/ /, "", $5); print $5; }')
    echo "Artifact: '$ARTIFACT'" | tee "$MTA_RUN_LOG_FILE"

    # Skip if artifact is already in the .done file
    grep -x "$ARTIFACT" "$MTA_ARTIFACT_DONE_FILE" >/dev/null && (echo "Skip $ARTIFACT" | tee "$MTA_RUN_LOG_FILE") && continue
    
    # Trim first /; convert / to _; convert space to _
    ARTIFACT_UNDERSCORE="$ARTIFACT"
    ARTIFACT_UNDERSCORE="${ARTIFACT_UNDERSCORE#/}"
    ARTIFACT_UNDERSCORE=${ARTIFACT_UNDERSCORE#'https://'}
    ARTIFACT_UNDERSCORE="${ARTIFACT_UNDERSCORE////_}"
    ARTIFACT_UNDERSCORE="${ARTIFACT_UNDERSCORE// /_}"
    echo "Generate report for $ARTIFACT -> $ARTIFACT_UNDERSCORE"
    
    ARTIFACT_BASE_DIR="$MTA_REPORTS_OUTPUT_DIR/$ARTIFACT_UNDERSCORE"
    ARTIFACT_REPORT_DIR="$ARTIFACT_BASE_DIR/report"
    ARTIFACT_WORK_DIR="$ARTIFACT_BASE_DIR/workdir"
    ARTIFACT_LOG_FILE="$ARTIFACT_WORK_DIR/mta-cli.log"
    ARTIFACT_DOWNLOAD_FILE="$ARTIFACT_WORK_DIR/$(basename $ARTIFACT)"
    rm -rf "$ARTIFACT_BASE_DIR"
    mkdir -p "$ARTIFACT_WORK_DIR" || { echo "Failed to create workdir ARTIFACT_WORK_DIR=$ARTIFACT_WORK_DIR"; exit 1; }

    # Download artifact
    curl -sf -u "$NEXUS_USERNAME:$NEXUS_PASSWORD" -O "$ARTIFACT_DOWNLOAD_FILE" $ARTIFACT
    if [ $? != 0 ]; then
        echo "Error downloading $ARTIFACT." | tee "$MTA_RUN_LOG_FILE"
        continue
    fi

    # Run MTA
    echo "$MTA_HOME/bin/mta-cli" --batchMode --exportCSV --overwrite -input "$ARTIFACT_DOWNLOAD_FILE" --output "$ARTIFACT_REPORT_DIR" --target cloud-readiness | tee "$MTA_RUN_LOG_FILE"
    "$MTA_HOME/bin/mta-cli" --batchMode --exportCSV --overwrite -input "$ARTIFACT_DOWNLOAD_FILE" --output "$ARTIFACT_REPORT_DIR" --target cloud-readiness 2>&1 | tee "$ARTIFACT_LOG_FILE"
    if [ $? != 0 -o ! -z "$(grep 'ERROR:' $ARTIFACT_REPORT_DIR.log)" ]; then
        echo "Error for $ARTIFACT." | tee "$MTA_RUN_LOG_FILE"
        continue
    fi

    # Mark as done
    echo "$ARTIFACT" >>"$MTA_ARTIFACT_DONE_FILE"
    echo "Done $ARTIFACT" | tee "$MTA_RUN_LOG_FILE"
done





