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

# Main installation process
main() {
    # Clean up Docker and Tutor
    cleanup_tutor
    cleanup_docker

    # Install Tutor
    echo "Installing Tutor v3.12.6 (Ironwood)..."
    sudo curl -L "https://github.com/overhangio/tutor/releases/download/v3.12.6/tutor-$(uname -s)_$(uname -m)" -o /usr/local/bin/tutor
    sudo chmod 0755 /usr/local/bin/tutor

    # Initialize Tutor
    echo "Initializing Tutor..."
    tutor local quickstart -I

    echo "Tutor Ironwood installation completed!"
}

# Execute main function with error handling
main
if [ $? -ne 0 ]; then
    echo "Installation failed. Please check the error messages above."
    exit 1
fi