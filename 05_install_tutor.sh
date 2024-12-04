#!/bin/bash

# Define OpenEdX versions and their corresponding Tutor versions
# Using an array to maintain order and an associative array for mapping
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

# Function to clean up Docker resources
cleanup_docker() {
    echo -e "\n\033[1;33m=== CLEANING UP DOCKER RESOURCES ===\033[0m"
    
    # Stop all running containers
    echo -e "\n\033[1;34m>>> Stopping all Docker containers...\033[0m"
    if [ "$(docker ps -q)" ]; then
        docker stop $(docker ps -q)
    else
        echo "No running containers found."
    fi

    # Remove all containers
    echo -e "\n\033[1;34m>>> Removing all Docker containers...\033[0m"
    if [ "$(docker ps -a -q)" ]; then
        docker rm -f $(docker ps -a -q)
    else
        echo "No containers found."
    fi

    # Remove all volumes
    echo -e "\n\033[1;34m>>> Removing all Docker volumes...\033[0m"
    if [ "$(docker volume ls -q)" ]; then
        docker volume rm -f $(docker volume ls -q)
    else
        echo "No volumes found."
    fi

    # Remove all networks (except default ones)
    echo -e "\n\033[1;34m>>> Removing all custom Docker networks...\033[0m"
    if [ "$(docker network ls --filter type=custom -q)" ]; then
        docker network rm $(docker network ls --filter type=custom -q)
    else
        echo "No custom networks found."
    fi

    # Remove all images
    echo -e "\n\033[1;34m>>> Removing all Docker images...\033[0m"
    if [ "$(docker images -q)" ]; then
        docker rmi -f $(docker images -q)
    else
        echo "No images found."
    fi

    # Prune system
    echo -e "\n\033[1;34m>>> Pruning Docker system...\033[0m"
    docker system prune -af --volumes

    echo -e "\n\033[1;32m=== DOCKER CLEANUP COMPLETED ===\033[0m\n"
}

# Check if tvm is installed
check_tvm() {
    if ! command -v tvm &> /dev/null; then
        echo "TVM is not installed. Installing TVM..."
        pip install tvm
        if [ $? -ne 0 ]; then
            echo "Failed to install TVM. Please check your Python installation."
            exit 1
        fi
    fi
}

# Display available versions
display_versions() {
    echo "Available OpenEdX versions:"
    for i in "${!ORDERED_VERSIONS[@]}"; do
        version=${ORDERED_VERSIONS[$i]}
        echo "$((i+1))) $version (Tutor v${VERSION_MAP[$version]})"
    done
}

# Main installation process
main() {
    # Clean up Docker resources first
    cleanup_docker

    check_tvm

    # Display versions and get user selection
    display_versions
    
    while true; do
        read -p "Select OpenEdX version (1-${#ORDERED_VERSIONS[@]}): " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#ORDERED_VERSIONS[@]}" ]; then
            selected_version=${ORDERED_VERSIONS[$((selection-1))]}
            tutor_version=${VERSION_MAP[$selected_version]}
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done

    echo "You selected: $selected_version (Tutor v$tutor_version)"
    read -p "Continue with installation? (y/n): " confirm
    if [[ $confirm != [yY] ]]; then
        echo "Installation cancelled."
        exit 1
    fi

    # Install specific Tutor version using TVM
    echo "Installing Tutor v$tutor_version..."
    tvm install "v$tutor_version"
    if [ $? -ne 0 ]; then
        echo "Failed to install Tutor version $tutor_version"
        exit 1
    fi

    # Initialize project
    echo "Initializing project for $selected_version..."
    tvm project init "$selected_version" "v$tutor_version"
    if [ $? -ne 0 ]; then
        echo "Failed to initialize project"
        exit 1
    fi

    # Change directory and activate virtual environment
    cd "$selected_version" || exit 1
    source .tvm/bin/activate

    # Run appropriate launch command based on version
    echo "Launching Tutor..."
    if (( $(echo "$tutor_version" | cut -d. -f1) >= 15 )); then
        echo "Running tutor local launch -I"
        tutor local launch -I
    else
        echo "Running tutor local quickstart -I"
        tutor local quickstart -I
    fi
}

# Execute main function with error handling
main
if [ $? -ne 0 ]; then
    echo "Installation failed. Please check the error messages above."
    exit 1
fi

echo "Installation completed successfully!"