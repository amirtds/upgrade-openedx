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

# Function to setup virtual environment
setup_venv() {
    echo -e "\n\033[1;34m>>> Setting up virtual environment\033[0m"
    
    # Install python3-venv if not already installed
    if ! dpkg -l | grep -q python3-venv; then
        echo "Installing python3-venv..."
        sudo apt-get update
        sudo apt-get install -y python3-venv
    fi
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "tutor-venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv tutor-venv
    fi
    
    # Activate virtual environment
    echo "Activating virtual environment..."
    source tutor-venv/bin/activate
    
    # Upgrade pip
    echo "Upgrading pip..."
    pip install --upgrade pip
}

# Function to upgrade to next version
upgrade_to_version() {
    local current_version=$1
    local target_version=$2
    local tutor_version=${VERSION_MAP[$target_version]}
    
    echo -e "\n\033[1;34m>>> Upgrading from $current_version to $target_version\033[0m"
    
    # Install new Tutor version using pip
    echo "Installing Tutor version $tutor_version..."
    pip install "tutor[full]==$tutor_version"
    if [ $? -ne 0 ]; then
        echo "Failed to install Tutor version $tutor_version"
        exit 1
    fi

    # Run upgrade
    echo "Running upgrade process..."
    tutor local upgrade --from="$current_version"
    
    # Special handling for Nutmeg version
    if [ "$target_version" = "nutmeg" ]; then
        echo -e "\n\033[1;33m=== Running Nutmeg-specific commands ===\033[0m"
        echo "Running backfill_course_tabs..."
        tutor local run cms ./manage.py cms backfill_course_tabs
        
        echo "Running simulate_publish..."
        tutor local run cms ./manage.py cms simulate_publish
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

    echo -e "\033[1;32m>>> Successfully upgraded to $target_version\033[0m"
}

# Main upgrade process
main() {
    # Setup virtual environment
    setup_venv
    
    local current_version="ironwood"
    
    for next_version in "${ORDERED_VERSIONS[@]}"; do
        echo -e "\n\033[1;35m=== Starting upgrade to $next_version ===\033[0m"
        upgrade_to_version "$current_version" "$next_version"
        current_version="$next_version"
    done
    
    # Deactivate virtual environment
    deactivate
}

# Execute main function with error handling
main
if [ $? -ne 0 ]; then
    echo "Upgrade failed. Please check the error messages above."
    exit 1
fi

