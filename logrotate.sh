#!/bin/bash

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI is not installed. Please install it first."
        exit 1
    fi
}

# Function to rotate logs
rotate_logs() {
    local LOG_DIR="$1"
    local S3_BUCKET="$2"
    
    # Ensure log directory exists
    if [ ! -d "$LOG_DIR" ]; then
        echo "Directory '$LOG_DIR' does not exist."
        exit 1
    fi

    echo "Scanning for log files in: $LOG_DIR"
    LOG_FILES=($(find "$LOG_DIR" -name "*.log" -type f))

    if [ ${#LOG_FILES[@]} -eq 0 ]; then
        echo "No log files found to process."
        exit 0
    fi

    for LOG_FILE in "${LOG_FILES[@]}"; do
        GZ_FILE="${LOG_FILE}.gz"

        # Compress the log file while keeping the original filename
        gzip -c "$LOG_FILE" > "$GZ_FILE"

        # Upload to S3
        aws s3 cp "$GZ_FILE" "$S3_BUCKET"

        if [ $? -eq 0 ]; then
            echo "Upload successful: $S3_BUCKET/$(basename "$GZ_FILE")"
            rm -f "$LOG_FILE"  # Remove original log file
            rm -f "$GZ_FILE"    # Remove compressed log file
            echo "Deleted local copies: $LOG_FILE and $GZ_FILE"
        else
            echo "Upload failed for $LOG_FILE. Keeping files."
        fi
    done
}

# Function to schedule log rotation via cron
schedule_log_rotation() {
    local SCRIPT_PATH="$(realpath "$0")"
    local LOG_DIR="$1"
    local S3_BUCKET="$2"
    local CRON_SCHEDULE="$3"

    # Add cron job
    CRON_JOB="$CRON_SCHEDULE bash $SCRIPT_PATH \"$LOG_DIR\" \"$S3_BUCKET\""

    # Check if the job is already in crontab
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_JOB") | crontab -

    echo "Log rotation scheduled with cron: $CRON_SCHEDULE"
}

# Main script execution
echo "Enter the directory to scan (leave empty for current directory):"
read LOG_DIR
LOG_DIR=${LOG_DIR:-$(pwd)}

echo "Enter S3 bucket URL (e.g., s3://my-bucket/logs/):"
read S3_BUCKET

echo "Choose mode: (manual/schedule) [default: manual]:"
read MODE
MODE=${MODE:-manual}

check_aws_cli  # Ensure AWS CLI is installed

if [ "$MODE" == "manual" ]; then
    rotate_logs "$LOG_DIR" "$S3_BUCKET"
elif [ "$MODE" == "schedule" ]; then
    echo "Enter cron schedule (e.g., '0 2 * * *' for daily at 2 AM):"
    read CRON_SCHEDULE
    schedule_log_rotation "$LOG_DIR" "$S3_BUCKET" "$CRON_SCHEDULE"
else
    echo "Invalid mode. Exiting."
    exit 1
fi
