#!/bin/bash
# Safe database sync using pg_dump --clean
# No DROP DATABASE required!

set -euo pipefail

FROM_ENV=${1:-production}
TO_ENV=${2:-staging}

# Source environment configurations
source /home/deploy/.env.${FROM_ENV}
FROM_DB_URL=$DATABASE_URL

source /home/deploy/.env.${TO_ENV}
TO_DB_URL=$DATABASE_URL

echo "Syncing database from ${FROM_ENV} to ${TO_ENV}..."

# Create backup directory
BACKUP_DIR="/home/deploy/db-backups"
mkdir -p $BACKUP_DIR
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup target database before sync
echo "Backing up ${TO_ENV} database..."
pg_dump $TO_DB_URL | gzip > "${BACKUP_DIR}/${TO_ENV}_backup_${TIMESTAMP}.sql.gz"

# Dump with --clean flag (adds DROP statements)
echo "Dumping ${FROM_ENV} database with clean option..."
DUMP_FILE="${BACKUP_DIR}/${FROM_ENV}_export_${TIMESTAMP}.sql"

if [ "$TO_ENV" = "staging" ]; then
    # For staging, exclude ETL tracking data
    pg_dump $FROM_DB_URL \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        --exclude-table-data=etl_runs \
        --exclude-table-data=etl_logs \
        -f "$DUMP_FILE"
    
    # Remove DROP/CREATE EXTENSION statements that require superuser
    sed -i '/^DROP EXTENSION/d' "$DUMP_FILE"
    sed -i '/^CREATE EXTENSION/d' "$DUMP_FILE"
    sed -i '/^COMMENT ON EXTENSION/d' "$DUMP_FILE"
else
    pg_dump $FROM_DB_URL \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        -f "$DUMP_FILE"
    
    # Remove DROP EXTENSION statements that require superuser
    sed -i '/^DROP EXTENSION/d' "$DUMP_FILE"
fi

# Stop any connections (optional, but helps avoid conflicts)
echo "Preparing ${TO_ENV} database..."
psql $TO_DB_URL -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();" || true

# Restore with clean dump (this drops/recreates all objects)
echo "Restoring to ${TO_ENV} database..."
psql $TO_DB_URL -v ON_ERROR_STOP=1 -f "$DUMP_FILE"

# Clean up
rm -f "$DUMP_FILE"

# Keep last 5 backups
echo "Cleaning up old backups..."
cd $BACKUP_DIR
ls -t *.sql.gz | tail -n +6 | xargs rm -f || true

echo "Database sync completed successfully!"
echo "Backup saved to: ${BACKUP_DIR}/${TO_ENV}_backup_${TIMESTAMP}.sql.gz"