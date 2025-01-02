#!/bin/bash

# Define OpenEdX versions and their corresponding Tutor versions
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

# Function to install older Tutor versions (binary method)
install_old_tutor() {
    local version=$1
    local tutor_version=${VERSION_MAP[$version]}
    
    echo "Installing Tutor v$tutor_version ($version) using binary method..."
    sudo curl -L "https://github.com/overhangio/tutor/releases/download/v$tutor_version/tutor-$(uname -s)_$(uname -m)" -o /usr/local/bin/tutor
    sudo chmod 0755 /usr/local/bin/tutor
}

# Function to setup virtual environment
setup_venv() {
    echo -e "\n\033[1;33m=== SETTING UP VIRTUAL ENVIRONMENT ===\033[0m"
    
    # Install required packages
    sudo apt update
    sudo apt install -y python3-venv python3-pip libyaml-dev
    
    # Create and activate virtual environment
    python3 -m venv /home/ubuntu/tutor-venv
    source /home/ubuntu/tutor-venv/bin/activate
    
    echo -e "\n\033[1;32m=== VIRTUAL ENVIRONMENT READY ===\033[0m\n"
}

# Function to clean up Docker resources (safely)
cleanup_docker() {
    echo -e "\n\033[1;33m=== CLEANING UP DOCKER RESOURCES (SAFELY) ===\033[0m"
    
    # Stop all running containers
    echo -e "\n\033[1;34m>>> Stopping all Docker containers...\033[0m"
    if [ "$(docker ps -q)" ]; then
        docker stop $(docker ps -q)
    fi

    # Remove all containers (but keep volumes!)
    echo -e "\n\033[1;34m>>> Removing all Docker containers...\033[0m"
    if [ "$(docker ps -a -q)" ]; then
        docker rm -f $(docker ps -a -q)
    fi

    # Remove custom networks (except default ones)
    echo -e "\n\033[1;34m>>> Removing custom Docker networks...\033[0m"
    if [ "$(docker network ls --filter type=custom -q)" ]; then
        docker network rm $(docker network ls --filter type=custom -q)
    fi

    echo -e "\n\033[1;32m=== DOCKER CLEANUP COMPLETED ===\033[0m\n"
}

# Function to upgrade to next version
upgrade_to_version() {
    local current_version=$1
    local target_version=$2
    local tutor_version=${VERSION_MAP[$target_version]}
    
    echo -e "\n\033[1;34m>>> Upgrading from $current_version to $target_version\033[0m"
    
    # Stop containers and clean up Docker resources (safely)
    echo "Stopping current containers..."
    tutor local stop
    cleanup_docker
    
    # Install Tutor based on version
    if [ "$target_version" = "juniper" ] || [ "$target_version" = "koa" ]; then
        install_old_tutor "$target_version"
    else
        echo "Installing Tutor version $tutor_version using pip..."
        pip install "tutor[full]==$tutor_version"
    fi

    if [ $? -ne 0 ]; then
        echo "Failed to install Tutor version $tutor_version"
        exit 1
    fi

    # Save configuration before upgrade
    echo "Saving Tutor configuration..."
    tutor config save

    # Run upgrade
    echo "Running upgrade process..."
    tutor local upgrade --from="$current_version"
    
    # Special handling for Nutmeg version
    if [ "$target_version" = "nutmeg" ]; then
        echo -e "\n\033[1;33m=== Running Nutmeg-specific commands ===\033[0m"
        
        # Run backfill commands
        echo "Running backfill_course_tabs..."
        tutor local run cms ./manage.py cms backfill_course_tabs
        
        echo "Running simulate_publish..."
        tutor local run cms ./manage.py cms simulate_publish

        # Verify course versions
        echo "Verifying course versions..."
        tutor local run lms ./manage.py lms shell -c "from openedx.core.djangoapps.content.course_overviews.models import CourseOverview; print('Course versions:', [(c.id, c.version) for c in CourseOverview.objects.all()])"
    fi

    # Launch services based on version
    echo "Launching Tutor with new version..."
    if (( $(echo "$tutor_version" | cut -d. -f1) >= 15 )); then
        echo "Running tutor local launch -I"
        tutor local launch -I
    else
        echo "Running tutor local quickstart -I"
        tutor local quickstart -I
    fi

    # Additional verification steps
    if [ "$target_version" = "nutmeg" ] || [ "$target_version" = "maple" ]; then
        echo -e "\n\033[1;33m=== Verifying database state ===\033[0m"
        
        # Check MySQL course versions
        echo "Checking course versions in MySQL..."
        tutor local run lms ./manage.py lms dbshell -c "SELECT id, version FROM course_overviews_courseoverview;"
        
        # Check MongoDB state
        echo "Checking MongoDB collections..."
        tutor local run mongodb mongo openedx --eval "db.modulestore.structures.count()"
        tutor local run mongodb mongo cs_comments_service --eval "db.contents.count()"
    fi

    echo -e "\033[1;32m>>> Successfully upgraded to $target_version\033[0m"
}

# Main upgrade process
main() {
    local current_version="ironwood"
    
    # Setup virtual environment first
    setup_venv
    
    # Verify system requirements
    echo "Verifying system requirements..."
    if ! command -v docker &> /dev/null; then
        echo "Docker is required but not installed. Please install Docker first."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose is required but not installed. Please install Docker Compose first."
        exit 1
    fi
    
    for next_version in "${ORDERED_VERSIONS[@]}"; do
        echo -e "\n\033[1;35m=== Starting upgrade to $next_version ===\033[0m"
        upgrade_to_version "$current_version" "$next_version"
        current_version="$next_version"
        
        # Give some time for services to stabilize
        echo "Waiting for services to stabilize..."
        sleep 30
    done

    echo -e "\n\033[1;32m=== UPGRADE PROCESS COMPLETED ===\033[0m"
    echo "Please verify that all services are running correctly."
    echo "You may want to run 'docker system prune' to clean up unused images and free up disk space."
}

# Execute main function with error handling
main
if [ $? -ne 0 ]; then
    echo "Upgrade failed. Please check the error messages above."
    exit 1
fi

