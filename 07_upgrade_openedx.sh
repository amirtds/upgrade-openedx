#!/bin/bash

# Define OpenEdX versions and their corresponding Tutor versions (same as in 05_install_tutor.sh)
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
    local from_version=$1
    local to_version=$2
    local tutor_version=${VERSION_MAP[$to_version]}
    
    echo "Upgrading from $from_version to $to_version (Tutor v$tutor_version)"
    
    # Install specific Tutor version using TVM
    echo "Installing Tutor v$tutor_version..."
    tvm install "v$tutor_version"
    if [ $? -ne 0 ]; then
        echo "Failed to install Tutor version $tutor_version"
        exit 1
    fi

    # Initialize project
    echo "Initializing project for $to_version..."
    tvm project init "$to_version" "v$tutor_version"
    if [ $? -ne 0 ]; then
        echo "Failed to initialize project"
        exit 1
    fi

    # Change directory and activate virtual environment
    cd "$to_version" || exit 1
    source .tvm/bin/activate

    # Run upgrade command if not the first version
    if [ -n "$from_version" ]; then
        echo "Running upgrade from $from_version..."
        tutor local upgrade --from="$from_version"
    fi

    # Run appropriate launch command based on version
    echo "Launching Tutor..."
    if (( $(echo "$tutor_version" | cut -d. -f1) >= 15 )); then
        tutor local launch -I
    else
        tutor local quickstart -I
    fi

    # Run additional CMS commands
    echo "Running CMS commands..."
    tutor local run cms sh -c "./manage.py cms reindex_course --all"
    tutor local run cms sh -c "./manage.py cms backfill_course_outlines"
    tutor local run cms sh -c "./manage.py cms simulate_publish"
    tutor local run cms sh -c "./manage.py cms generate_course_overview --all-courses"

    echo "Upgrade to $to_version completed successfully!"
}

# Main upgrade process
main() {
    # Get current version
    current_version=$(get_current_version)
    echo "Current version: $current_version"

    # Get target version
    echo "Available target versions:"
    local start_listing=false
    for i in "${!ORDERED_VERSIONS[@]}"; do
        version=${ORDERED_VERSIONS[$i]}
        if [ "$version" = "$current_version" ]; then
            start_listing=true
            continue
        fi
        if [ "$start_listing" = true ]; then
            echo "$((i+1))) $version (Tutor v${VERSION_MAP[$version]})"
        fi
    done

    read -p "Select target version (enter number or 'all' for step-by-step upgrade): " selection

    if [ "$selection" = "all" ]; then
        # Perform step-by-step upgrade
        while true; do
            next_version=$(get_next_version "$current_version")
            if [ -z "$next_version" ]; then
                break
            fi
            
            upgrade_to_version "$current_version" "$next_version"
            current_version=$next_version
        done
    else
        # Upgrade to specific version
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            target_version=${ORDERED_VERSIONS[$((selection-1))]}
            while [ "$current_version" != "$target_version" ]; do
                next_version=$(get_next_version "$current_version")
                if [ -z "$next_version" ]; then
                    break
                fi
                upgrade_to_version "$current_version" "$next_version"
                current_version=$next_version
            done
        else
            echo "Invalid selection"
            exit 1
        fi
    fi
}

# Execute main function
main

echo "Upgrade process completed successfully!"