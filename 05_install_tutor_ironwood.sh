#!/bin/bash

# Function to clean up Docker resources
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

# Function to validate file exists
validate_file() {
    local file_path=$1
    local file_type=$2
    
    if [ ! -f "$file_path" ]; then
        echo "Error: $file_type file not found at $file_path"
        return 1
    fi
    return 0
}

# Function to validate directory exists
validate_directory() {
    local dir_path=$1
    
    if [ ! -d "$dir_path" ]; then
        echo "Error: Directory not found at $dir_path"
        return 1
    fi
    return 0
}

# Main installation process
main() {
    # Get file paths from user
    read -p "Enter the path to MySQL dump file (.sql): " mysql_dump
    read -p "Enter the path to MongoDB backup directory: " mongo_backup

    # Validate inputs
    validate_file "$mysql_dump" "MySQL dump"
    if [ $? -ne 0 ]; then exit 1; fi
    
    validate_directory "$mongo_backup"
    if [ $? -ne 0 ]; then exit 1; fi

    # Clean up Docker resources
    cleanup_docker

    # Install Tutor
    echo "Installing Tutor v3.12.6 (Ironwood)..."
    sudo curl -L "https://github.com/overhangio/tutor/releases/download/v3.12.6/tutor-$(uname -s)_$(uname -m)" -o /usr/local/bin/tutor
    sudo chmod 0755 /usr/local/bin/tutor
    
    # Set proper permissions
    sudo chown -R $USER:$USER ~/.local/share/tutor

    # Initialize Tutor
    echo "Initializing Tutor..."
    tutor local quickstart -I

    # Wait for containers to be ready
    echo "Waiting for containers to be ready..."
    sleep 10

    # Get MySQL credentials from environment
    echo "Setting up database credentials..."
    LOCAL_TUTOR_MYSQL_ROOT_USERNAME="root"
    LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
    LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data"

    # Restore MySQL database
    echo "Restoring MySQL database..."
    docker exec -i tutor_local_mysql_1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD -e \"DROP DATABASE IF EXISTS openedx;\""
    docker exec -i tutor_local_mysql_1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" < "$mysql_dump"

    # Restore MongoDB
    echo "Restoring MongoDB databases..."
    sudo cp -R "$mongo_backup" "$LOCAL_TUTOR_DATA_DIRECTORY/mongodb/backup/"
    docker exec -i tutor_local_mongodb_1 sh -c 'exec mongorestore --drop -d edxapp /data/db/backup/edxapp/'
    docker exec -i tutor_local_mongodb_1 sh -c 'exec mongorestore --drop -d cs_comments_service /data/db/backup/cs_comments_service/'

    # Verify MySQL restore
    echo "Verifying MySQL restore..."
    docker exec -i tutor_local_mysql_1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD -D openedx -e \"SELECT count(*) FROM auth_user;\""

    # Run migrations
    echo "Running database migrations..."
    tutor local run lms sh -c "./manage.py lms makemigrations"
    tutor local run lms sh -c "./manage.py lms migrate"

    echo "Installation and database restoration completed!"
}

# Execute main function with error handling
main
if [ $? -ne 0 ]; then
    echo "Installation failed. Please check the error messages above."
    exit 1
fi