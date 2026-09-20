#!/bin/bash

# This script restores your data from a backup archive.
# Launch it in the docker compose folder

# Usage function
usage() {
    echo "Usage: $0 pg-version <backup_file_path_or_s3_url> [s3-endpoint] [s3-access-key] [s3-secret-key] [s3-region]"
    echo "Restore Plumber. You must run this CLI from the root of your Plumber local git repository"
    echo
    echo "Options:"
    echo "  pg-version                  Version of PostgreSQL you are using"
    echo "  backup_file_path_or_s3_url  Path to the backup file to restore or S3 URL (s3://bucket-name/folder/backup-file.tar.gz)"
    echo "  s3-endpoint                 S3 endpoint (https://s3-endpoint-url)"
    echo "  s3-region                   S3 bucket region"
    echo "  s3-access-key               S3 Access Key ID"
    echo "  s3-secret-key               S3 Secret Access Key"
    echo "  -h, --help                  Display this help message"
}

# Define some consts
PROJECT_NAME=plumber

# Get arguments
PG_VERSION=$1
BACKUP_SOURCE=$2
S3_ENDPOINT=$3
S3_REGION=$4
S3_ACCESS_KEY=$5
S3_SECRET_KEY=$6


# Check if --help or -h is provided as the first argument
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
    exit 1
fi

# Ensure a backup file path or S3 URL is specified
if [ -z "$BACKUP_SOURCE" ]; then
  printf "Error: backup file path or S3 URL is missing\n"
  usage
  exit 1
fi

# Temporary directory for downloaded backup if from S3
TMP_DIR=""
LOCAL_BACKUP_FILE=""

# Check if the backup source is an S3 URL
if [[ $BACKUP_SOURCE == s3://* ]]; then
    echo "🔄 Downloading backup file from S3..."

    # Parse S3 URL to get the key
    S3_KEY=$(echo "$BACKUP_SOURCE" | sed -n 's|^s3://[^/]*/\(.*\)|\1|p')
    LOCAL_BACKUP_FILE=$(basename "$S3_KEY")
    TMP_DIR=$(mktemp -d)

    # Configure AWS credentials temporarily
    export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY
    export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY

    # Prepare the AWS CLI command
    S3_CLI_CMD="aws s3 cp \"$BACKUP_SOURCE\" \"$TMP_DIR/$LOCAL_BACKUP_FILE\" --region \"$S3_REGION\" --endpoint-url \"$S3_ENDPOINT\""

    # Download the file from S3
    if eval "$S3_CLI_CMD"; then
        echo "✅ Backup file downloaded from S3 to $TMP_DIR/$LOCAL_BACKUP_FILE"
    else
        echo "❌ Error while downloading backup file from S3"
        exit 1
    fi
    BACKUP_FILE="$TMP_DIR/$LOCAL_BACKUP_FILE"

    # Unset AWS credentials after use
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY

else
    # Use the provided local backup file path
    BACKUP_FILE=$(realpath "$BACKUP_SOURCE")
fi

# Ensure the backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    printf "Error: backup file %s does not exist\n" "$BACKUP_FILE"
    usage
    exit 1
fi

echo "🛳️ Start restoring data..."

# Extract the backup
BACKUP_DIR=$(mktemp -d)
tar xzf "$BACKUP_FILE" -C "$BACKUP_DIR"

echo "Restoring the .env file..."
if cp "$BACKUP_DIR/.env" ./.env; then
    echo "✅ The .env file has been restored"
    # shellcheck disable=SC1091
    source .env
    PLUMBER_DB_HOST="${PLUMBER_DB_HOST:-postgres}"
    PLUMBER_DB_USER="${PLUMBER_DB_USER:-plumber}"
    PLUMBER_DB_NAME="${PLUMBER_DB_NAME:-plumber}"
else
    echo "❌ Error while restoring the .env file"
    exit 1
fi

if [ -d "$BACKUP_DIR/ca-certificates" ]; then
    echo "Restoring the custom CA certificates..."
    mkdir -p .docker/ca-certificates
    if cp "$BACKUP_DIR"/ca-certificates/* .docker/ca-certificates/; then
        echo "✅ Custom CA certificates have been restored"
        bash scripts/ca-bundle.sh
    else
        echo "❌ Error while restoring the custom CA certificates"
        exit 1
    fi
fi

echo "Restoring the database..."
export PGPASSWORD="$PLUMBER_DB_PASSWORD"
if docker run --rm --network="${PROJECT_NAME}_intranet" -v "$BACKUP_DIR":/backup -e PGPASSWORD -it postgres:"$PG_VERSION" /bin/bash -c "pg_restore -U \"$PLUMBER_DB_USER\" -h \"$PLUMBER_DB_HOST\" --if-exists -c -e -Ft -d \"$PLUMBER_DB_NAME\" /backup/db_backup.tar"; then

    echo "✅ Database has been restored"
else
    echo "❌ Error while restoring database"
    exit 1
fi
unset PGPASSWORD

# Cleanup
rm -rf "$BACKUP_DIR"
if [ -n "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
fi

echo "🧹 Cleanup done"
