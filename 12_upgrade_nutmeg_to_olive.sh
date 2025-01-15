#!/bin/bash

ORDERED_VERSIONS=(
    "juniper"
    "koa"
    "lilac"
    "maple"
    "nutmeg"
    "olive"
    "palm"
    "quince"
    "redwood"
)

declare -A VERSION_MAP=(
    ["juniper"]="10.5.3"
    ["koa"]="11.3.1"
    ["lilac"]="12.2.0"
    ["maple"]="13.3.1"
    ["nutmeg"]="14.2.3"
    ["olive"]="15.3.7"
    ["palm"]="16.1.8"
    ["quince"]="17.0.6"
    ["redwood"]="18.1.4"
)

# Set environment variables
export LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data/"
export LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
export LOCAL_TUTOR_MYSQL_ROOT_USERNAME=$(tutor config printvalue MYSQL_ROOT_USERNAME)

# Add color variables at the top of the script
BLUE='\033[1;34m'
NC='\033[0m' # No Color

cleanup_docker() {
    echo -e "\n\033[1;33m=== CLEANING UP DOCKER RESOURCES ===\033[0m"
    
    # Stop all running containers
    echo -e "\n\033[1;34m>>> Stopping all Docker containers...\033[0m"
    if [ "$(docker ps -q)" ]; then
        docker stop $(docker ps -q)
    fi

    # Remove all containers
    echo -e "\n\033[1;34m>>> Removing all Docker containers...\033[0m"
    if [ "$(docker ps -a -q)" ]; then
        docker rm -f $(docker ps -a -q)
    fi

    # Remove all volumes
    echo -e "\n\033[1;34m>>> Removing all Docker volumes...\033[0m"
    if [ "$(docker volume ls -q)" ]; then
        docker volume rm -f $(docker volume ls -q)
    fi

    # Remove all networks (except default ones)
    echo -e "\n\033[1;34m>>> Removing custom Docker networks...\033[0m"
    if [ "$(docker network ls --filter type=custom -q)" ]; then
        docker network rm $(docker network ls --filter type=custom -q)
    fi

    echo -e "\n\033[1;32m=== DOCKER CLEANUP COMPLETED ===\033[0m\n"
}

# Function to clean up Tutor
cleanup_tutor() {
    echo -e "\n\033[1;33m=== CLEANING UP TUTOR ===\033[0m"
    
    # Remove Tutor data
    if [ -d ~/.local/share/tutor ]; then
        echo "Removing Tutor data..."
        sudo rm -rf ~/.local/share/tutor
    fi

    # Remove Tutor executable
    if [ -f /usr/local/bin/tutor ]; then
        echo "Removing Tutor executable..."
        sudo rm -f /usr/local/bin/tutor
    fi

    echo -e "\n\033[1;32m=== TUTOR CLEANUP COMPLETED ===\033[0m\n"
}

# 1. Export Nutmeg DB
# -------------------------------
## Create export directory for Nutmeg
EXPORT_DIR="nutmeg_export"
echo -e "${BLUE}Creating export directory: $EXPORT_DIR${NC}"
mkdir -p "$EXPORT_DIR"

## Export MySQL databases
echo -e "${BLUE}Exporting MySQL databases...${NC}"
docker exec -i tutor_local_mysql_1 mysqldump -u root -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" --databases openedx > "$EXPORT_DIR/openedx.sql"

## Export MongoDB databases
echo -e "${BLUE}Exporting MongoDB databases...${NC}"
docker exec -i tutor_local_mongodb_1 mongodump --out=/data/db/dump/
docker exec -i tutor_local_mongodb_1 bash -c "cd /data/db/dump && tar czf /data/db/mongodb_dump.tar.gz ."
docker cp tutor_local_mongodb_1:/data/db/mongodb_dump.tar.gz "$EXPORT_DIR/"

echo -e "${BLUE}Export completed successfully!${NC}"
echo -e "${BLUE}Files are stored in: $EXPORT_DIR${NC}"


# 2. Install Olive and import Nutmeg DB
# -------------------------------

# Clean up Docker and Tutor
cleanup_docker
cleanup_tutor

## Install Nutmeg
sudo curl -L "https://github.com/overhangio/tutor/releases/download/v15.3.7/tutor-$(uname -s)_$(uname -m)" -o /usr/local/bin/tutor
sudo chmod 0755 /usr/local/bin/tutor

echo -e "${BLUE}Installing Tutor v15.3.7 (Nutmeg)...${NC}"
tutor local launch -I

echo -e "${BLUE}Tutor Nutmeg installation completed!${NC}"

# Set environment variables
export LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data"
export LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
export LOCAL_TUTOR_MYSQL_ROOT_USERNAME=$(tutor config printvalue MYSQL_ROOT_USERNAME)


## Import Nutmeg DB
echo -e "${BLUE}Importing Nutmeg DB...${NC}"

# Copy MongoDB backup
echo -e "${BLUE}Copying MongoDB backup...${NC}"
MONGO_BACKUP_DIR="$LOCAL_TUTOR_DATA_DIRECTORY/mongodb/backup/"
sudo mkdir -p "$MONGO_BACKUP_DIR"
sudo cp -R "$EXPORT_DIR/mongodb_dump.tar.gz" "$MONGO_BACKUP_DIR"

# extract the mongodb_dump.tar.gz file
echo -e "${BLUE}Extracting MongoDB backup...${NC}"
sudo tar -xzf "$MONGO_BACKUP_DIR/mongodb_dump.tar.gz" -C "$MONGO_BACKUP_DIR"

# Restore MongoDB backups
echo -e "${BLUE}Restoring MongoDB backups...${NC}"
docker exec -i tutor_local_mongodb_1 sh -c 'exec mongorestore --drop -d openedx /data/db/backup/openedx/'
docker exec -i tutor_local_mongodb_1 sh -c 'exec mongorestore --drop -d cs_comments_service /data/db/backup/cs_comments_service/'

# Drop and restore MySQL database
echo -e "${BLUE}Restoring MySQL database...${NC}"
docker exec -i tutor_local_mysql_1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD -e \"DROP DATABASE IF EXISTS openedx; CREATE DATABASE openedx;\""

# Import with progress bar
echo -e "${BLUE}Importing database (this may take a while)...${NC}"
pv -s $(stat --format=%s "$EXPORT_DIR/openedx.sql") "$EXPORT_DIR/openedx.sql" | docker exec -i tutor_local_mysql_1 mysql \
    -u"$LOCAL_TUTOR_MYSQL_ROOT_USERNAME" \
    -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" \
    --init-command="SET SESSION foreign_key_checks=0;" \
    openedx

# Run remaining migrations
echo -e "${BLUE}Running migrations...${NC}"
tutor local run lms sh -c "python manage.py lms migrate"
tutor local run cms sh -c "python manage.py cms migrate"

# Run additional CMS commands
echo -e "${BLUE}Running CMS commands...${NC}"
tutor local run cms sh -c "./manage.py cms simulate_publish"
tutor local run cms sh -c "./manage.py cms generate_course_overview --all-courses"

# Verify data restoration
echo -e "\n${BLUE}=== VERIFYING DATA RESTORATION ===${NC}"

# Get MySQL counts
mysql_status=0
user_count=$(docker exec -i tutor_local_mysql_1 mysql -u root -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM openedx.auth_user;" 2>/dev/null) || mysql_status=$?
course_count=$(docker exec -i tutor_local_mysql_1 mysql -u root -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM openedx.course_overviews_courseoverview;" 2>/dev/null) || mysql_status=$?

# Get MongoDB counts
mongo_status=0
modulestore_count=$(docker exec -i tutor_local_mongodb_1 mongo openedx --quiet --eval "db.modulestore.active_versions.count()" 2>/dev/null) || mongo_status=$?
forum_count=$(docker exec -i tutor_local_mongodb_1 mongo cs_comments_service --quiet --eval "db.contents.count()" 2>/dev/null) || mongo_status=$?

# Display results
if [ $mysql_status -eq 0 ] && [ $mongo_status -eq 0 ]; then
    echo -e "\n${BLUE}✅ Database restoration completed successfully!${NC}"
    echo -e "${BLUE}MySQL Users: $user_count${NC}"
    echo -e "${BLUE}MySQL Courses: $course_count${NC}"
    echo -e "${BLUE}MongoDB Modulestore Items: $modulestore_count${NC}"
    echo -e "${BLUE}MongoDB Forum Items: $forum_count${NC}"
else
    echo -e "\n${BLUE}⚠️ Database restoration completed with warnings. Please verify the data manually.${NC}"
fi

echo -e "\n${BLUE}=== VERIFICATION COMPLETED ===${NC}\n"