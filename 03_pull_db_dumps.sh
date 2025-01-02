#!/bin/bash

# Constants
BUCKET_NAME="prod-hawthorn-gymnasium-backups"

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    echo "Error: gsutil is not installed. Please install Google Cloud SDK first."
    exit 1
fi

# Check if user is authenticated
if ! gsutil ls gs://${BUCKET_NAME} &> /dev/null; then
    echo "Error: Unable to access bucket. Please make sure you're authenticated with 'gcloud auth login'"
    exit 1
fi

# Function to list files in bucket
list_files() {
    echo "Available files in bucket:"
    gsutil ls gs://${BUCKET_NAME} | sed "s|gs://${BUCKET_NAME}/||"
}

# Function to download a file
download_file() {
    local file_name=$1
    local full_path="gs://${BUCKET_NAME}/${file_name}"
    
    # Check if file exists
    if gsutil ls "${full_path}" &> /dev/null; then
        echo "Downloading ${file_name}..."
        gsutil cp "${full_path}" .
        
        # Process mongo backup if it's a tar.gz file
        if [[ $file_name == *.tar.gz ]]; then
            echo "Extracting mongo backup..."
            current_datetime=$(date '+%Y%m%d_%H%M%S')
            tar -xzf "${file_name}"
            extracted_dir=$(tar -tzf "${file_name}" | head -1 | cut -f1 -d"/")
            if [ -n "$extracted_dir" ]; then
                mv "$extracted_dir" "mongo_backup_${current_datetime}"
                echo "Mongo backup extracted and renamed to: mongo_backup_${current_datetime}"
            fi
        fi
        
        echo "Download complete!"
    else
        echo "Error: File '${file_name}' not found in bucket"
        return 1
    fi
}

# Main loop
while true; do
    echo -e "\nWhat would you like to do?"
    echo "1. List files in bucket"
    echo "2. Download MySQL dump (.sql)"
    echo "3. Download MongoDB backup (.tar.gz)"
    echo "4. Exit"
    read -p "Enter your choice (1-4): " choice

    case $choice in
        1)
            list_files
            ;;
        2)
            list_files
            echo ""
            read -p "Enter the MySQL dump file name (must end with .sql, or 'q' to go back): " file_name
            if [ "$file_name" = "q" ]; then
                continue
            fi
            if [[ $file_name != *.sql ]]; then
                echo "Error: File must be a .sql file"
                continue
            fi
            download_file "$file_name"
            ;;
        3)
            list_files
            echo ""
            read -p "Enter the MongoDB backup file name (must end with .tar.gz, or 'q' to go back): " file_name
            if [ "$file_name" = "q" ]; then
                continue
            fi
            if [[ $file_name != *.tar.gz ]]; then
                echo "Error: File must be a .tar.gz file"
                continue
            fi
            download_file "$file_name"
            ;;
        4)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
done