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

# Function to upgrade to next version
upgrade_to_version() {
    local current_version=$1
    local target_version=$2
    local tutor_version=${VERSION_MAP[$target_version]}
    
    echo -e "\n\033[1;34m>>> Upgrading from $current_version to $target_version\033[0m"
    
    # Install Tutor based on version
    if [ "$target_version" = "juniper" ] || [ "$target_version" = "koa" ]; then
        install_old_tutor "$target_version"
    else
        echo "Installing Tutor version $tutor_version using pip..."
        sudo pip3 install "tutor[full]==$tutor_version"
    fi

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
    local current_version="ironwood"
    
    for next_version in "${ORDERED_VERSIONS[@]}"; do
        echo -e "\n\033[1;35m=== Starting upgrade to $next_version ===\033[0m"
        upgrade_to_version "$current_version" "$next_version"
        current_version="$next_version"
    done
}

# Execute main function with error handling
main
if [ $? -ne 0 ]; then
    echo "Upgrade failed. Please check the error messages above."
    exit 1
fi

