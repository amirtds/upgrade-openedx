#!/bin/bash

# Set environment variables
export LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data/"
export LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
export LOCAL_TUTOR_MYSQL_ROOT_USERNAME=$(tutor config printvalue MYSQL_ROOT_USERNAME)

# Function to prompt for MySQL dump file
select_mysql_dump() {
    echo "Available MySQL dump files:"
    sql_files=(*.sql)
    if [ ${#sql_files[@]} -eq 0 ]; then
        echo "No .sql files found in current directory!"
        exit 1
    fi

    for i in "${!sql_files[@]}"; do
        echo "$((i+1))) ${sql_files[$i]}"
    done

    while true; do
        read -p "Select MySQL dump file (1-${#sql_files[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#sql_files[@]}" ]; then
            MYSQL_DUMP_FILE="${sql_files[$((selection-1))]}"
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
    if [ ${#mongo_dirs[@]} -eq 0 ]; then
        echo "No mongo* directories found in current directory!"
        exit 1
    fi

    for i in "${!mongo_dirs[@]}"; do
        echo "$((i+1))) ${mongo_dirs[$i]}"
    done

    while true; do
        read -p "Select MongoDB dump directory (1-${#mongo_dirs[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#mongo_dirs[@]}" ]; then
            MONGO_DUMP_DIR="${mongo_dirs[$((selection-1))]}"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

# Function to verify MySQL data
verify_mysql_data() {
    echo "Verifying MySQL data..."
    
    # Check user count
    user_count=$(docker exec -i tutor_local-mysql-1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD openedx -e 'SELECT COUNT(*) as count FROM auth_user;'" | grep -v count)
    echo "Total users found: $user_count"
    
    # Check course count
    course_count=$(docker exec -i tutor_local-mysql-1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD openedx -e 'SELECT COUNT(*) as count FROM course_overviews_courseoverview;'" | grep -v count)
    echo "Total courses found: $course_count"
    
    if [ "$user_count" -eq "0" ] || [ "$course_count" -eq "0" ]; then
        echo "Warning: Some tables appear to be empty!"
        return 1
    fi
    return 0
}

# Function to verify MongoDB data
verify_mongo_data() {
    echo "Verifying MongoDB data..."
    
    # Check modulestore count
    modulestore_count=$(docker exec -i tutor_local-mongodb-1 sh -c 'echo "db.modulestore.structures.count()" | mongo openedx --quiet')
    echo "Modulestore structures found: $modulestore_count"
    
    # Check forum count
    forum_count=$(docker exec -i tutor_local-mongodb-1 sh -c 'echo "db.contents.count()" | mongo cs_comments_service --quiet')
    echo "Forum contents found: $forum_count"
    
    if [ "$modulestore_count" -eq "0" ] || [ "$forum_count" -eq "0" ]; then
        echo "Warning: Some MongoDB collections appear to be empty!"
        return 1
    fi
    return 0
}

# Main restoration process
main() {
    # Prompt user for files
    select_mysql_dump
    select_mongo_dump

    # Confirm selections
    echo -e "\nSelected MySQL dump file: $MYSQL_DUMP_FILE"
    echo "Selected MongoDB dump directory: $MONGO_DUMP_DIR"
    read -p "Proceed with these selections? (y/n): " confirm
    if [[ $confirm != [yY] ]]; then
        echo "Operation cancelled."
        exit 1
    fi

    # Copy MongoDB backup
    echo "Copying MongoDB backup..."
    MONGO_BACKUP_DIR="$LOCAL_TUTOR_DATA_DIRECTORY/mongodb/backup/"
    sudo mkdir -p "$MONGO_BACKUP_DIR"
    sudo cp -R "$MONGO_DUMP_DIR"/* "$MONGO_BACKUP_DIR"

    # Restore MongoDB backups
    echo "Restoring MongoDB backups..."
    docker exec -i tutor_local-mongodb-1 sh -c 'exec mongorestore --drop -d openedx /data/db/backup/edxapp/'
    docker exec -i tutor_local-mongodb-1 sh -c 'exec mongorestore --drop -d cs_comments_service /data/db/backup/cs_comments_service/'

    # Drop and restore MySQL database
    echo "Restoring MySQL database..."
    docker exec -i tutor_local-mysql-1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD -e \"DROP DATABASE IF EXISTS openedx; CREATE DATABASE openedx;\""
    docker exec -i tutor_local-mysql-1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD openedx" < "$MYSQL_DUMP_FILE"
    # Run remaining migrations
    echo "Running remaining migrations..."
    tutor local run lms sh -c "python manage.py lms migrate"
    tutor local run cms sh -c "python manage.py cms migrate"

    # Verify data restoration
    echo -e "\nVerifying data restoration..."
    verify_mysql_data
    mysql_status=$?
    verify_mongo_data
    mongo_status=$?

    # Run additional CMS commands
    echo "Running CMS commands..."
    tutor local run cms sh -c "./manage.py cms reindex_course --all"
    tutor local run cms sh -c "./manage.py cms simulate_publish"
    tutor local run cms sh -c "./manage.py cms generate_course_overview --all-courses"

    # Cleanup MongoDB backup directory
    echo "Cleaning up MongoDB backup directory..."
    sudo rm -rf "$LOCAL_TUTOR_DATA_DIRECTORY/mongodb/backup"

    # Final status
    if [ $mysql_status -eq 0 ] && [ $mongo_status -eq 0 ]; then
        echo -e "\n✅ Database restoration completed successfully!"
        echo "MySQL Users: $user_count"
        echo "MySQL Courses: $course_count"
        echo "MongoDB Modulestore Items: $modulestore_count"
        echo "MongoDB Forum Items: $forum_count"
    else
        echo -e "\n⚠️ Database restoration completed with warnings. Please verify the data manually."
    fi
}

# Execute main function with error handling
main
if [ $? -ne 0 ]; then
    echo "Restoration failed. Please check the error messages above."
    exit 1
fi