#!/bin/bash

# This script creates a backup of your data inside an archive.
# Launch it in the docker compose folder

# Usage function
usage() {
    echo "Usage: $0 pg-version [s3-destination] [s3-endpoint] [s3-access-key] [s3-secret-key] [s3-region]"
    echo "Backup Plumber. You must run this CLI from the root of your Plumber local git repository"
    echo
    echo "Options:"
    echo "  pg-version      Version of PostgreSQL you are using"
    echo "  s3-destination  Name of the S3 bucket and path to upload the backup (s3://bucket-name/folder)"
    echo "  s3-endpoint     S3 endpoint (https://s3-endpoint-url)"
    echo "  s3-region       S3 bucket region"
    echo "  s3-access-key   S3 Access Key ID"
    echo "  s3-secret-key   S3 Secret Access Key"
    echo "  -h, --help      Display this help message"
}

# Source Plumber configuration
# shellcheck disable=SC1091
source .env
PLUMBER_DB_HOST="${PLUMBER_DB_HOST:-postgres}"
PLUMBER_DB_USER="${PLUMBER_DB_USER:-plumber}"
PLUMBER_DB_NAME="${PLUMBER_DB_NAME:-plumber}"

# Define some consts
BACKUPS_DIR=backups
BACKUP_NAME=backup_plumber-$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_PATH="$BACKUPS_DIR/$BACKUP_NAME"
PROJECT_NAME=plumber

# Check if --help or -h is provided as the first argument
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
    exit 0
fi

# Get arguments
PG_VERSION=$1
S3_DESTINATION=$2
S3_ENDPOINT=$3
S3_REGION=$4
S3_ACCESS_KEY=$5
S3_SECRET_KEY=$6

# Create the backup directory
mkdir -p "$BACKUP_PATH"
echo "📦 Start backing up data..."

# Backup the database
echo "Saving the database..."
export PGPASSWORD="$PLUMBER_DB_PASSWORD"
if docker run --rm --network="${PROJECT_NAME}_intranet" -v "$PWD/$BACKUP_PATH":/backup -e PGPASSWORD postgres:"$PG_VERSION" /bin/bash -c "pg_dump -U \"$PLUMBER_DB_USER\" -h \"$PLUMBER_DB_HOST\" -d \"$PLUMBER_DB_NAME\" -Ft -f /db_backup.tar && mv db_backup.tar /backup"; then
    echo "✅ Database has been saved"
else
    echo "❌ Error while saving database"
    exit 1
fi
unset PGPASSWORD

# Backup the `.env` file:
echo "Saving the .env file..."
if cp .env "$BACKUP_PATH"; then
    echo "✅ The .env file has been saved"
    echo "ℹ️  .env holds PLUMBER_TOKEN_ENCRYPTION_KEY: the database dump is unreadable without it. Store this archive safely."
else
    echo "❌ Error while saving the .env file"
    exit 1
fi

# Backup the custom CA certificates (if any):
if find .docker/ca-certificates -maxdepth 1 -type f \( -name "*.pem" -o -name "*.crt" \) | grep -q .; then
    echo "Saving the custom CA certificates..."
    mkdir -p "$BACKUP_PATH/ca-certificates"
    if cp .docker/ca-certificates/*.pem .docker/ca-certificates/*.crt "$BACKUP_PATH/ca-certificates/" 2>/dev/null; then
        echo "✅ Custom CA certificates have been saved"
    else
        echo "❌ Error while saving the custom CA certificates"
        exit 1
    fi
fi

# Create a tar.gz archive of the backup
echo "Archiving the backup..."
if tar -czf "$BACKUP_PATH.tar.gz" -C "$BACKUP_PATH" .; then
    echo "✅ Backup has been archived"
else
    echo "❌ Error while archiving backup"
    exit 1
fi

# Remove the backup folder after compression
echo "Cleaning up temporary backup folder..."
if rm -rf "$BACKUP_PATH"; then
    echo "✅ Temporary backup folder has been removed"
else
    echo "⚠️ Warning: Could not remove temporary backup folder"
fi

# Optional: Upload the backup to S3 if the bucket name is provided
if [ -n "$S3_DESTINATION" ]; then
    echo "Uploading the backup to S3..."

    # Configure AWS credentials temporarily
    export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY
    export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY

    # Remove the "s3://" prefix from S3_DESTINATION if it exists
    S3_DESTINATION_CLEANED=$(echo "$S3_DESTINATION" | sed 's/^s3:\/\///')

    # Construct the S3 URI
    S3_URI="s3://$S3_DESTINATION_CLEANED/$BACKUP_NAME.tar.gz"

    # Prepare the AWS CLI command
    S3_CLI_CMD="aws s3 cp \"$BACKUP_PATH.tar.gz\" \"$S3_URI\" --region \"$S3_REGION\" --endpoint-url \"$S3_ENDPOINT\""

    # Execute the AWS CLI command
    if eval "$S3_CLI_CMD"; then
        echo "✅ Backup has been uploaded to S3 bucket $S3_DESTINATION at $S3_URI"
        # Remove local archive after successful upload
        if rm -f "$BACKUP_PATH.tar.gz"; then
            echo "✅ Local archive has been removed"
        else
            echo "⚠️ Warning: Could not remove local archive"
        fi
    else
        echo "❌ Error while uploading backup to S3"
    fi

    # Unset AWS credentials after use
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
else
    echo "⏭️ Skipping S3 upload as AWS credentials or bucket name were not provided."
fi
