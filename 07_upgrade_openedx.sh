#!/bin/bash

# Define OpenEdX versions and their corresponding Tutor versions
ORDERED_VERSIONS=(
    "ironwood"
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
    ["ironwood"]="3.12.6"
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

# Function to get current version from previous installation
get_current_version() {
    local current_dir=$(pwd)
    for version in "${ORDERED_VERSIONS[@]}"; do
        if [ -d "$current_dir/$version" ]; then
            echo "$version"
            return 0
        fi
    done
    echo "No existing OpenEdX installation found!"
    exit 1
}

# Function to get next version
get_next_version() {
    local current_version=$1
    local found=false
    local next_version=""
    
    for version in "${ORDERED_VERSIONS[@]}"; do
        if [ "$found" = true ]; then
            next_version=$version
            break
        fi
        if [ "$version" = "$current_version" ]; then
            found=true
        fi
    done
    
    echo "$next_version"
}

# Function to upgrade to next version
upgrade_to_version() {
    local current_version=$1
    local target_version=$2
    local tutor_version=${VERSION_MAP[$target_version]}
    
    echo -e "\n\033[1;34m>>> Upgrading from $current_version to $target_version using TVM...\033[0m"
    
    # Create backup first
    BACKUP_DIR="backup_${current_version}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup existing data
    echo "Creating backup..."
    tutor local exec mysql mysqldump -u root --password="$(tutor config printvalue MYSQL_ROOT_PASSWORD)" openedx > "$BACKUP_DIR/mysql_backup.sql"
    tutor local exec mongodb mongodump --out=/data/db/backup/
    docker cp tutor_local_mongodb_1:/data/db/backup/. "$BACKUP_DIR/mongodb/"
    cp config.yml "$BACKUP_DIR/config.yml"

    # Stop and remove current containers
    echo "Stopping and removing current containers..."
    tutor local stop
    tutor local dc down -v   # Remove volumes but keep data
    docker system prune -f    # Clean up unused images

    # Install new Tutor version using TVM
    echo "Installing Tutor version v$tutor_version..."
    tvm install "v$tutor_version"
    if [ $? -ne 0 ]; then
        echo "Failed to install Tutor version $tutor_version"
        exit 1
    fi

    # Use the new version
    echo "Switching to Tutor version v$tutor_version..."
    tvm use "v$tutor_version"
    if [ $? -ne 0 ]; then
        echo "Failed to switch to Tutor version $tutor_version"
        exit 1
    fi

    # Pull new images
    echo "Pulling new Docker images..."
    tutor images pull
    if [ $? -ne 0 ]; then
        echo "Failed to pull new Docker images"
        exit 1
    fi

    # Run upgrade
    echo "Running upgrade process..."
    tutor config save
    tutor local upgrade --from "$current_version"
    
    # Launch services based on version
    echo "Launching Tutor with new version..."
    if (( $(echo "$tutor_version" | cut -d. -f1) >= 15 )); then
        echo "Running tutor local launch -I"
        tutor local launch -I
    else
        echo "Running tutor local quickstart -I"
        tutor local quickstart -I
    fi

    # Verify new versions
    echo -e "\n\033[1;36m=== Verifying Docker containers versions ===\033[0m"
    docker ps | grep "openedx"

    echo -e "\033[1;32m>>> Successfully upgraded to $target_version\033[0m"
    echo -e "\033[1;33mBackup saved in: $BACKUP_DIR\033[0m"
}

# Main upgrade process
main() {
    # Get current version
    current_version=$(get_current_version)
    echo -e "\n\033[1;36m=== CURRENT VERSION: $current_version ===\033[0m"

    # Display available versions
    echo -e "\n\033[1;36m=== AVAILABLE TARGET VERSIONS: ===\033[0m"
    local start_listing=false
    for i in "${!ORDERED_VERSIONS[@]}"; do
        version=${ORDERED_VERSIONS[$i]}
        if [ "$version" = "$current_version" ]; then
            start_listing=true
            continue
        fi
        if [ "$start_listing" = true ]; then
            echo -e "\033[1;36m$((i+1))) $version (Tutor v${VERSION_MAP[$version]})\033[0m"
        fi
    done

    read -p $'\n\033[1;33mSelect target version (enter number or "all" for step-by-step upgrade): \033[0m' selection

    if [ "$selection" = "all" ]; then
        echo -e "\n\033[1;34m>>> Starting step-by-step upgrade process...\033[0m"
        while true; do
            next_version=$(get_next_version "$current_version")
            if [ -z "$next_version" ]; then
                break
            fi
            
            upgrade_to_version "$current_version" "$next_version"
            current_version=$next_version
        done
    else
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            target_version=${ORDERED_VERSIONS[$((selection-1))]}
            echo -e "\n\033[1;34m>>> Starting upgrade process to $target_version...\033[0m"
            while [ "$current_version" != "$target_version" ]; do
                next_version=$(get_next_version "$current_version")
                if [ -z "$next_version" ]; then
                    break
                fi
                upgrade_to_version "$current_version" "$next_version"
                current_version=$next_version
            done
        else
            echo -e "\n\033[1;31m!!! Invalid selection\033[0m"
            exit 1
        fi
    fi
}

# Execute main function
main

echo -e "\n\033[1;32m=== UPGRADE PROCESS COMPLETED SUCCESSFULLY! ===\033[0m\n"