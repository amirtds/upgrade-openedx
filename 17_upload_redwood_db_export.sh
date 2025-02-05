#!/bin/bash

# Set environment variables
export LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data/"
export LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
export LOCAL_TUTOR_MYSQL_ROOT_USERNAME=$(tutor config printvalue MYSQL_ROOT_USERNAME)

# Add color variables at the top of the script
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Set GCP bucket name and backup directory
GCP_BUCKET="prod-hawthorn-gymnasium-backups"
BACKUP_DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="redwood_backup_${BACKUP_DATE}"

# 1. Export Redwood DB
# -------------------------------
## Create export directory for Redwood
EXPORT_DIR="redwood_export"
echo -e "${BLUE}Creating export directory: $EXPORT_DIR${NC}"
mkdir -p "$EXPORT_DIR"

## Export MySQL databases
echo -e "${BLUE}Exporting MySQL databases...${NC}"
docker exec -i tutor_local-mysql-1 mysqldump -u root -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" --databases openedx > "$EXPORT_DIR/openedx.sql"

## Export MongoDB databases
echo -e "${BLUE}Exporting MongoDB databases...${NC}"
docker exec -i tutor_local-mongodb-1 mongodump --out=/data/db/dump/
docker exec -i tutor_local-mongodb-1 bash -c "cd /data/db/dump && tar czf /data/db/mongodb_dump.tar.gz ."
docker cp tutor_local-mongodb-1:/data/db/mongodb_dump.tar.gz "$EXPORT_DIR/"

echo -e "${BLUE}Export completed successfully!${NC}"
echo -e "${BLUE}Files are stored in: $EXPORT_DIR${NC}"

# 2. Create compressed backup
# -------------------------------
echo -e "${BLUE}Creating compressed backup...${NC}"
tar czf "${BACKUP_DIR}.tar.gz" "$EXPORT_DIR"

# 3. Upload to GCP Storage
# -------------------------------
echo -e "${BLUE}Uploading backup to GCP Storage bucket: $GCP_BUCKET${NC}"

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    echo -e "${BLUE}gsutil not found. Please install Google Cloud SDK first.${NC}"
    exit 1
fi

# Check if user is authenticated with GCP
if ! gsutil ls "gs://${GCP_BUCKET}" &> /dev/null; then
    echo -e "${BLUE}Unable to access GCP bucket. Please authenticate with 'gcloud auth login' first.${NC}"
    exit 1
fi

# Upload the backup
gsutil cp "${BACKUP_DIR}.tar.gz" "gs://${GCP_BUCKET}/${BACKUP_DIR}/"

# Verify upload
if gsutil ls "gs://${GCP_BUCKET}/${BACKUP_DIR}/${BACKUP_DIR}.tar.gz" &> /dev/null; then
    echo -e "${BLUE}✅ Backup successfully uploaded to GCP Storage!${NC}"
    echo -e "${BLUE}Backup location: gs://${GCP_BUCKET}/${BACKUP_DIR}/${BACKUP_DIR}.tar.gz${NC}"
    
    # Clean up local backup files
    echo -e "${BLUE}Cleaning up local backup files...${NC}"
    rm -rf "$EXPORT_DIR" "${BACKUP_DIR}.tar.gz"
else
    echo -e "${BLUE}⚠️ Upload verification failed. Please check the GCP Storage bucket manually.${NC}"
fi

echo -e "\n${BLUE}=== BACKUP PROCESS COMPLETED ===${NC}\n"
