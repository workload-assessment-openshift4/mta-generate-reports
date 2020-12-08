#!/bin/bash

# Avoid tee overwriting error code 
set -o pipefail

MTA_ARTIFACT_LIST_FILE="${1:-$MTA_ARTIFACT_LIST_FILE}"
MTA_ARTIFACT_DONE_FILE="${MTA_ARTIFACT_DONE_FILE:-$MTA_ARTIFACT_LIST_FILE.done}"
MTA_REPORTS_OUTPUT_DIR="${2:-$MTA_REPORTS_OUTPUT_DIR}"

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

touch $MTA_ARTIFACT_DONE_FILE || { echo "Can't write file MTA_ARTIFACT_DONE_FILE=$MTA_ARTIFACT_DONE_FILE"; exit 1; }
mkdir -p $MTA_REPORTS_OUTPUT_DIR || { echo "Failed to create MTA_REPORTS_OUTPUT_DIR=$MTA_REPORTS_OUTPUT_DIR"; exit 1; }


# Loop over artifact list
cat $MTA_ARTIFACT_LIST_FILE | while read -r ARTIFACT
do
    # Skip if artifact is already in the .done file
    grep -x "$ARTIFACT" $MTA_ARTIFACT_DONE_FILE >/dev/null && echo "Skip $ARTIFACT" && continue
    
    # Trim first /; covert / to _; convert space to _
    ARTIFACT_UNDERSCORE="$ARTIFACT"
    ARTIFACT_UNDERSCORE="${ARTIFACT_UNDERSCORE#/}"
    ARTIFACT_UNDERSCORE="${ARTIFACT_UNDERSCORE////_}"
    ARTIFACT_UNDERSCORE="${ARTIFACT_UNDERSCORE// /_}"
    echo "Generate report for $ARTIFACT -> $ARTIFACT_UNDERSCORE"
    
    ARTIFACT_REPORT_DIR=$MTA_REPORTS_OUTPUT_DIR/$ARTIFACT_UNDERSCORE

    # Run MTA
    echo $MTA_HOME/bin/mta-cli --batchMode --exportCSV --overwrite -input $ARTIFACT --output $ARTIFACT_REPORT_DIR --target cloud-readiness
    $MTA_HOME/bin/mta-cli --batchMode --exportCSV --overwrite -input $ARTIFACT --output $ARTIFACT_REPORT_DIR --target cloud-readiness 2>&1 | tee $ARTIFACT_REPORT_DIR.log
    if [ $? != 0 -o ! -z "$(grep 'ERROR:' $ARTIFACT_REPORT_DIR.log)" ]; then
        echo "Error for $ARTIFACT."
        continue
    fi

    # Mark as done
    echo "$ARTIFACT" >>$MTA_ARTIFACT_DONE_FILE
    echo "Done $ARTIFACT"
done





