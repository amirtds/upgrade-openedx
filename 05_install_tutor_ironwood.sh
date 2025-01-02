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

# Function to list and select files
select_file() {
    local file_type=$1
    local extension=$2
    local files=()
    
    echo -e "\nAvailable ${file_type} files:"
    
    # List files with numbers
    local i=1
    while IFS= read -r file; do
        echo "$i) $file"
        files+=("$file")
        ((i++))
    done < <(ls *.${extension} 2>/dev/null)
    
    if [ ${#files[@]} -eq 0 ]; then
        echo "No ${file_type} files found in current directory"
        return 1
    fi
    
    # Get user selection
    local selection
    while true; do
        read -p "Select a number (1-${#files[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#files[@]}" ]; then
            break
        fi
        echo "Invalid selection. Please try again."
    done
    
    echo "${files[$selection-1]}"
    return 0
}

# Function to list and select mongo backup directories
select_directory() {
    local dirs=()
    
    echo -e "\nAvailable MongoDB backup directories:"
    
    # List directories with numbers
    local i=1
    while IFS= read -r dir; do
        if [ -d "$dir" ] && [[ "$dir" == mongo_* ]]; then
            echo "$i) $dir"
            dirs+=("$dir")
            ((i++))
        fi
    done < <(ls -d */ 2>/dev/null)
    
    if [ ${#dirs[@]} -eq 0 ]; then
        echo "No MongoDB backup directories (starting with 'mongo_') found in current directory"
        return 1
    fi
    
    # Get user selection
    local selection
    while true; do
        read -p "Select a number (1-${#dirs[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#dirs[@]}" ]; then
            break
        fi
        echo "Invalid selection. Please try again."
    done
    
    echo "${dirs[$selection-1]}"
    return 0
}

# Main installation process
main() {
    # Select MySQL dump file
    echo "Selecting MySQL dump file..."
    mysql_dump=$(select_file "MySQL dump" ".sql")
    if [ $? -ne 0 ]; then
        echo "Error: No MySQL dump files found"
        exit 1
    fi
    
    # Select MongoDB backup directory
    echo "Selecting MongoDB backup directory..."
    mongo_backup=$(select_directory)
    if [ $? -ne 0 ]; then
        echo "Error: No MongoDB backup directories found"
        exit 1
    fi

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