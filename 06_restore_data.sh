#!/bin/bash

# Set environment variables
export LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data/"
export LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
export LOCAL_TUTOR_MYSQL_ROOT_USERNAME=$(tutor config printvalue MYSQL_ROOT_USERNAME)

# Function to prompt for MySQL dump file
select_mysql_dump() {
    echo "Available MySQL dump files:"
    sql_files=(*.sql)
    for i in "${!sql_files[@]}"; do
        echo "$((i+1))) ${sql_files[$i]}"
    done

    while true; do
        read -p "Select MySQL dump file (1-${#sql_files[@]}) or enter a custom filename: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#sql_files[@]}" ]; then
            MYSQL_DUMP_FILE="${sql_files[$((selection-1))]}"
            break
        elif [ -f "$selection" ]; then
            MYSQL_DUMP_FILE="$selection"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

# Function to prompt for MongoDB dump directory
select_mongo_dump() {
    echo "Available MongoDB dump directories:"
    mongo_dirs=(mongo*/)
    for i in "${!mongo_dirs[@]}"; do
        echo "$((i+1))) ${mongo_dirs[$i]}"
    done

    while true; do
        read -p "Select MongoDB dump directory (1-${#mongo_dirs[@]}) or enter a custom directory: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#mongo_dirs[@]}" ]; then
            MONGO_DUMP_DIR="${mongo_dirs[$((selection-1))]}"
            break
        elif [ -d "$selection" ]; then
            MONGO_DUMP_DIR="$selection"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

# Prompt user for MySQL dump file and MongoDB dump directory
select_mysql_dump
select_mongo_dump

# Confirm selections
echo "Selected MySQL dump file: $MYSQL_DUMP_FILE"
echo "Selected MongoDB dump directory: $MONGO_DUMP_DIR"
read -p "Proceed with these selections? (y/n): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Copy MongoDB backup
echo "Copying MongoDB backup..."
MONGO_BACKUP_DIR="$LOCAL_TUTOR_DATA_DIRECTORY/mongodb/backup/"

# Create the backup directory if it doesn't exist
if [ ! -d "$MONGO_BACKUP_DIR" ]; then
    echo "Creating MongoDB backup directory..."
    sudo mkdir -p "$MONGO_BACKUP_DIR"
fi

sudo cp -R "$MONGO_DUMP_DIR"/* "$MONGO_BACKUP_DIR"

# Restore MongoDB backups for openedx and cs_comments_service databases
echo "Restoring MongoDB backups..."
docker exec -i tutor_local_mongodb_1 sh -c 'exec mongorestore --drop -d openedx /data/db/backup/openedx/'
docker exec -i tutor_local_mongodb_1 sh -c 'exec mongorestore --drop -d cs_comments_service /data/db/backup/cs_comments_service/'

# Drop old/vanilla MySQL database
echo "Dropping old MySQL database..."
docker exec -i tutor_local_mysql_1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD -e \"DROP DATABASE IF EXISTS openedx; CREATE DATABASE openedx;\""

# First restore the backup (this brings in all the base tables and data)
echo "Restoring MySQL backup..."
docker exec -i tutor_local_mysql_1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD openedx" < "$MYSQL_DUMP_FILE"

# Run fake migrations for problematic apps
echo "Running fake migrations for specific apps..."
tutor local run lms sh -c "python manage.py lms migrate content_type_gating 0001 --fake"
tutor local run lms sh -c "python manage.py lms migrate content_type_gating 0003 --fake"
tutor local run lms sh -c "python manage.py lms migrate course_duration_limits 0001 --fake"
tutor local run lms sh -c "python manage.py lms migrate course_duration_limits 0003 --fake"


# Finally run all remaining migrations
echo "Running remaining migrations..."
tutor local run lms sh -c "python manage.py lms migrate"
tutor local run cms sh -c "python manage.py cms migrate"

# Run additional CMS commands
echo "Running CMS commands..."
tutor local run cms sh -c "./manage.py cms reindex_course --all"
tutor local run cms sh -c "./manage.py cms simulate_publish"
tutor local run cms sh -c "./manage.py cms generate_course_overview --all-courses"

# Cleanup MongoDB backup directory
echo "Cleaning up MongoDB backup directory..."
sudo rm -rf "$LOCAL_TUTOR_DATA_DIRECTORY/mongodb/backup"

echo "Database restoration and command execution completed successfully!"