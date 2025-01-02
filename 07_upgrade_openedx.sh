#!/bin/bash

# -----------------------------------------------------------------------------
# Migrate Open edX from Ironwood to Redwood using Tutor
# -----------------------------------------------------------------------------

# Setup environment variables
LOCAL_BACKUP_PATH="/home/ubuntu/migration/backups/"
LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data/"
LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
LOCAL_TUTOR_MYSQL_ROOT_USERNAME=$(tutor config printvalue MYSQL_ROOT_USERNAME)

# Function to prepare directories
setup_directories() {
    echo -e "\n\033[1;33m=== Creating directory structure ===\033[0m"
    mkdir -p /home/ubuntu/migration/backups/mysql
    mkdir -p /home/ubuntu/migration/backups/mongodb
    mkdir -p /home/ubuntu/migration/upgraded
}

# Function to clean up Docker and Tutor (preserving data)
cleanup_environment() {
    echo -e "\n\033[1;33m=== Cleaning up environment (preserving data) ===\033[0m"
    
    # Stop containers
    if [ "$(docker ps -a -q)" ]; then
        docker stop $(docker ps -a -q)
        docker rm $(docker ps -a -q)
    fi
    
    # Remove unused images
    docker image prune -f
    
    # Remove Tutor installation but preserve config and data
    if command -v tutor &> /dev/null; then
        TUTOR_ROOT=$(tutor config printroot)
        TUTOR_CONFIG_FILE="$TUTOR_ROOT/config.yml"
        
        # Backup current config
        if [ -f "$TUTOR_CONFIG_FILE" ]; then
            cp "$TUTOR_CONFIG_FILE" "$TUTOR_CONFIG_FILE.backup"
        fi
        
        # Uninstall Tutor and plugins
        pip uninstall -y tutor-openedx tutor tutor-xqueue tutor-webui tutor-notes \
            tutor-minio tutor-mfe tutor-forum tutor-discovery tutor-android \
            tutor-cairn tutor-credentials tutor-indigo tutor-jupyter
            
        # Restore config
        if [ -f "$TUTOR_CONFIG_FILE.backup" ]; then
            mkdir -p "$TUTOR_ROOT"
            mv "$TUTOR_CONFIG_FILE.backup" "$TUTOR_CONFIG_FILE"
        fi
    fi
}

# Function to setup Python virtual environment
setup_venv() {
    echo -e "\n\033[1;33m=== Setting up virtual environment ===\033[0m"
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip setuptools
}

# Function to perform database operations
prepare_databases() {
    echo -e "\n\033[1;33m=== Preparing databases ===\033[0m"
    
    # Rename database from edxapp to openedx in dump file
    sed -i '/edxapp/ s//openedx/g' ${LOCAL_BACKUP_PATH}mysql/mysql-data.sql
    
    # Import MySQL data
    docker exec -i tutor_local_mysql_1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD -e 'DROP DATABASE IF EXISTS openedx;'"
    docker exec -i tutor_local_mysql_1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" < "${LOCAL_BACKUP_PATH}mysql/mysql-data.sql"
    
    # Import MongoDB data
    if [ -d "${LOCAL_TUTOR_DATA_DIRECTORY}mongodb/backup" ]; then
        sudo rm -r "${LOCAL_TUTOR_DATA_DIRECTORY}mongodb/backup"
    fi
    
    # Setup MongoDB backup directory
    sudo mkdir -p "${LOCAL_TUTOR_DATA_DIRECTORY}mongodb/backup"
    sudo cp -R "${LOCAL_BACKUP_PATH}mongodb/dump/"* "${LOCAL_TUTOR_DATA_DIRECTORY}mongodb/backup/"
    sudo chown -R systemd-coredump ${LOCAL_TUTOR_DATA_DIRECTORY}mongodb/backup
    sudo chgrp -R systemd-coredump ${LOCAL_TUTOR_DATA_DIRECTORY}mongodb/backup
    
    # Restore MongoDB
    docker exec -i tutor_local_mongodb_1 mongorestore --drop -d openedx /data/db/backup/edxapp/
}

# Main upgrade process
main() {
    echo -e "\n\033[1;32m=== Starting Open edX upgrade process ===\033[0m"
    
    # Initial setup
    setup_directories
    cleanup_environment
    setup_venv
    
    # Upgrade path following Tutor versions
    echo -e "\n\033[1;33m=== Starting upgrade path ===\033[0m"
    
    # Juniper (first step from Ironwood)
    pip install "tutor[full]==11.3.0"
    tutor local quickstart
    prepare_databases
    
    # Koa
    pip install "tutor[full]==12.2.0"
    tutor local upgrade --from=juniper
    tutor local quickstart
    
    # Lilac
    pip install "tutor[full]==13.3.1"
    tutor local upgrade --from=koa
    tutor local quickstart
    
    # Maple
    pip install "tutor[full]==14.2.4"
    tutor local upgrade --from=lilac
    tutor local quickstart
    
    # Nutmeg (with special handling)
    pip install "tutor[full]==14.2.4"
    tutor local upgrade --from=maple
    tutor local quickstart
    
    # Run Nutmeg-specific commands
    echo -e "\n\033[1;33m=== Running Nutmeg-specific commands ===\033[0m"
    tutor local run cms ./manage.py cms backfill_course_tabs
    tutor local run cms ./manage.py cms simulate_publish
    
    # Continue with remaining versions
    for version in "15.3.9:olive:nutmeg" "16.1.8:palm:olive" "17.0.6:quince:palm" "18.1.2:redwood:quince"; do
        IFS=: read tutor_version name prev_version <<< "$version"
        echo -e "\n\033[1;33m=== Upgrading to $name ===\033[0m"
        pip install "tutor[full]==$tutor_version"
        tutor local upgrade --from=$prev_version
        tutor local launch
    done
    
    # Setup system service
    echo -e "\n\033[1;33m=== Setting up system service ===\033[0m"
    sudo systemctl daemon-reload
    sudo systemctl enable tutor.service
    sudo systemctl start tutor.service
    
    echo -e "\n\033[1;32m=== Upgrade process completed ===\033[0m"
    echo "Please verify that all services are running correctly."
}

# Execute main function with error handling
main
if [ $? -ne 0 ]; then
    echo -e "\n\033[1;31m=== Upgrade failed. Please check the error messages above ===\033[0m"
    exit 1
fi

