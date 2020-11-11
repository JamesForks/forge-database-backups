#!/bin/sh

set -e

SCRIPT_STARTED_AT=$(date -u +"%Y-%m-%d %H:%M:%S")
BACKUP_STATUS=0
BACKUP_ARCHIVES=()

echo "Starting backup procedure at $SCRIPT_STARTED_AT"

for DATABASE in $BACKUP_DATABASES; do
    BACKUP_ARCHIVE_NAME="$DATABASE.sql.gz"
    BACKUP_ARCHIVE_PATH="$BACKUP_FULL_STORAGE_PATH$BACKUP_TIMESTAMP/$BACKUP_ARCHIVE_NAME"

    # Dump The Database, GZip And Upload To S3

    if [[ $SERVER_DATABASE_DRIVER == 'mysql' ]]
    then
        mysqldump \
            --user=root \
            --password=$SERVER_DATABASE_PASSWORD \
            --single-transaction \
            $DATABASE | \
            gzip -c | \
            aws s3 cp - $BACKUP_ARCHIVE_PATH \
            --profile=$BACKUP_AWS_PROFILE_NAME \
            ${BACKUP_AWS_ENDPOINT:+ --endpoint=$BACKUP_AWS_ENDPOINT}
    else
        sudo -u postgres pg_dump --clean -F p $DATABASE | \
        gzip -c | \
        aws s3 cp - $BACKUP_ARCHIVE_PATH \
            --profile=$BACKUP_AWS_PROFILE_NAME \
            ${BACKUP_AWS_ENDPOINT:+ --endpoint=$BACKUP_AWS_ENDPOINT}
    fi

    # Get The Size Of This File And Store It

    BACKUP_ARCHIVE_SIZE=$(aws s3 ls $BACKUP_ARCHIVE_PATH \
        --profile=$BACKUP_AWS_PROFILE_NAME \
        ${BACKUP_AWS_ENDPOINT:+ --endpoint=$BACKUP_AWS_ENDPOINT} | \
        awk '{print $3}')

    BACKUP_ARCHIVES+=($BACKUP_ARCHIVE_NAME $BACKUP_ARCHIVE_SIZE)
done

echo $BACKUP_ARCHIVESBACKUP_ARCHIVES_JSON=$(echo "[$(printf '{\"%s\": %d},' ${BACKUP_ARCHIVES[@]} | sed '$s/,$//')]")

curl -s --request POST \
    --url "$FORGE_PING_CALLBACK" \
    --data-urlencode "type=backup" \
    --data-urlencode "backup_token=$BACKUP_TOKEN" \
    --data-urlencode "streamed=true" \
    --data-urlencode "status=" \
    --data-urlencode "backup_configuration_id=$BACKUP_ID" \
    --data-urlencode "archives=$BACKUP_ARCHIVES_JSON" \
    --data-urlencode "archive_path=$BACKUP_FULL_STORAGE_PATH$BACKUP_TIMESTAMP" \
    --data-urlencode "started_at=$SCRIPT_STARTED_AT" \
    --data-urlencode "uuid=$BACKUP_UUID"

exit 0
