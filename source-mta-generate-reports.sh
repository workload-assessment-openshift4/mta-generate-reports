#!/bin/bash

# Avoid tee -a overwriting error code 
set -o pipefail

MTA_REPO_LIST_FILE="${1:-$MTA_REPO_LIST_FILE}"
MTA_REPORTS_OUTPUT_DIR="${2:-$MTA_REPORTS_OUTPUT_DIR}"
MTA_REPO_DONE_FILE="${MTA_REPO_DONE_FILE:-$MTA_REPORTS_OUTPUT_DIR/repos.done}"
MTA_RUN_LOG_FILE="${MTA_RUN_LOG_FILE:-$MTA_REPORTS_OUTPUT_DIR/report.log}"
MTA_POINTS_FILE="${MTA_POINTS_FILE:-$MTA_REPORTS_OUTPUT_DIR/points.csv}"

# Check parameters
if [ -z "$MTA_HOME" -o ! -f "$MTA_HOME/bin/mta-cli" ]; then
    echo "MTA_HOME is required. E.g. 'export MTA_HOME=/home/myuser/mta-cli-5.1.0.Final'"
    exit 1
fi

if [ -z "$MTA_REPO_LIST_FILE" -o -z "$MTA_REPORTS_OUTPUT_DIR" ]; then
    echo "Usage: ./source-mta-generate-reports.sh [MTA_REPO_LIST_FILE] [MTA_REPORTS_OUTPUT_DIR]
    The MTA_REPO_LIST_FILE input file is expected to contain the list of repos to scan, one per each line with format 'git-url,branch,subdirectory'. 
    The MTA_REPORTS_OUTPUT_DIR output directory is where the reports will be created."
    exit 1 
fi

mkdir -p "$MTA_REPORTS_OUTPUT_DIR" || { echo "Failed to create MTA_REPORTS_OUTPUT_DIR=$MTA_REPORTS_OUTPUT_DIR"; exit 1; }
touch "$MTA_REPO_DONE_FILE" || { echo "Can't write file MTA_REPO_DONE_FILE=$MTA_REPO_DONE_FILE"; exit 1; }
if [ ! -f "$MTA_POINTS_FILE" ]; then
    echo "URL,Repository,SubDirectory,Points,Total,Migration Optional,Cloud Mandatory,Cloud Optional,Information" >"$MTA_POINTS_FILE"
fi

# Loop over repo list
cat "$MTA_REPO_LIST_FILE" | while IFS="," read -r COL1 COL2 COL3 COL4 REPO BRANCH SUBDIR
do
    # Download url
    echo "Repo: '$REPO $SUBDIR'" | tee -a "$MTA_RUN_LOG_FILE"

    # Skip if repo is already in the .done file
    grep -x "$REPO $SUBDIR" "$MTA_REPO_DONE_FILE" >/dev/null && (echo "Skip $REPO" | tee -a "$MTA_RUN_LOG_FILE") && continue

    # Trim
    REPO_NAME_RAW=$(basename "$REPO")
    REPO_NAME=$(echo "${REPO_NAME_RAW%.*}" )
    echo "Generate report for $REPO -> $REPO_NAME"

    # REPO_BASE_DIR="$MTA_REPORTS_OUTPUT_DIR/$REPO_NAME-$SUBDIR" 
    if [ ! -z "$SUBDIR" ]; then
        SUBDIR_DASH=$(echo $SUBDIR | sed -e 's/\//-/g')
        REPO_BASE_DIR="$MTA_REPORTS_OUTPUT_DIR/$REPO_NAME-$SUBDIR_DASH" 
    else 
        REPO_BASE_DIR="$MTA_REPORTS_OUTPUT_DIR/$REPO_NAME"
    fi 
    REPO_REPORT_DIR="$REPO_BASE_DIR/report"
    REPO_WORK_DIR="$REPO_BASE_DIR/workdir"
    REPO_LOG_FILE="$REPO_WORK_DIR/mta-cli.log"
    REPO_CLONED_DIR="$REPO_WORK_DIR/$REPO_NAME"
    rm -rf "$REPO_BASE_DIR"
    mkdir -p "$REPO_WORK_DIR" || { echo "Failed to create workdir REPO_WORK_DIR=$REPO_WORK_DIR"; exit 1; }

    # Clone Repo
    (cd $REPO_WORK_DIR && git clone $REPO)
    if [ $? != 0 ]; then
        echo "Error cloning $REPO" 
        continue
    fi

    # Switch branch
    if [ ! -z "$BRANCH" ]; then
        cd $REPO_CLONED_DIR && git checkout "$BRANCH"
    fi

    # # Change to subdirectory
    # if [ ! -z "$SUBDIR" ]; then
    #     cd "$REPO_CLONED_DIR/$SUBDIR"
    # fi
    
    # Run MTA
    echo "$MTA_HOME/bin/mta-cli" --sourceMode --exportCSV --overwrite -input "$REPO_CLONED_DIR/$SUBDIR" --output "$REPO_REPORT_DIR" --target cloud-readiness
    "$MTA_HOME/bin/mta-cli" --sourceMode --exportCSV --overwrite -input "$REPO_CLONED_DIR/$SUBDIR" --output "$REPO_REPORT_DIR" --target cloud-readiness 2>&1 | tee -a "$REPO_LOG_FILE"
    if [ $? != 0 -o ! -z "$(grep 'ERROR:' $REPO_LOG_FILE)" ]; then
        echo "Error for $REPO." | tee -a "$MTA_RUN_LOG_FILE"
        continue
    fi

    #Parse points from index.html
    POINTS=$(cat $REPO_REPORT_DIR/index.html | grep '<span class="legend">story points</span>' -B1 -m1 | sed 's/[^0-9]*//g')
    NUM_TOTAL=$(cat $REPO_REPORT_DIR/index.html | grep '<td class="label_"> <span>Total</span> </td>' -B1 -m1| sed 's/[^0-9]*//g')
    NUM_OPTIONAL=$(cat $REPO_REPORT_DIR/index.html | grep '<td class="label_">Migration Optional</td>' -B1 -m1| sed 's/[^0-9]*//g')
    NUM_CLOUD_MANDATORY=$(cat $REPO_REPORT_DIR/index.html | grep '<td class="label_">Cloud Mandatory</td>' -B1 -m1| sed 's/[^0-9]*//g')
    NUM_CLOUD_OPTIONAL=$(cat $REPO_REPORT_DIR/index.html | grep '<td class="label_">Cloud Optional</td>' -B1 -m1| sed 's/[^0-9]*//g')
    NUM_INFORMATION=$(cat $REPO_REPORT_DIR/index.html | grep '<td class="label_">Information</td>' -B1 -m1| sed 's/[^0-9]*//g')

    echo "$REPO,$REPO_NAME,$SUBDIR,$POINTS,$NUM_TOTAL,$NUM_OPTIONAL,$NUM_CLOUD_MANDATORY,$NUM_CLOUD_OPTIONAL,$NUM_INFORMATION" | tee -a "$MTA_POINTS_FILE"

    # Mark as done
    echo "$REPO $SUBDIR" >>"$MTA_REPO_DONE_FILE"
    echo "Done: '$REPO $SUBDIR'" | tee -a "$MTA_RUN_LOG_FILE"


done
