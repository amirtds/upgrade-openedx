#!/bin/bash

# MySQL header to add to extracted files
MYSQL_HEADER='/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE="+00:00" */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE="NO_AUTO_VALUE_ON_ZERO" */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;'

# Add MySQL footer definition
MYSQL_FOOTER='/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;'

# Function to extract and modify database from dump
extract_and_modify_database() {
    local source_file=$1
    local db_name=$2
    local output_file="${db_name}_dump.sql"
    local next_db_pattern="-- Current Database: \`[^${db_name}]"

    echo "Extracting and modifying ${db_name} database to ${output_file}..."
    
    # Create temporary file
    temp_file=$(mktemp)
    
    # Extract database content
    sed -n -e "/-- Current Database: \`${db_name}\`/,/${next_db_pattern}/p" "$source_file" > "$temp_file"
    
    # Add header and append extracted content to final file
    echo "$MYSQL_HEADER" > "$output_file"
    cat "$temp_file" >> "$output_file"
    
    # Modify the SQL file
    sed -i '1iDROP DATABASE openedx;' "$output_file"
    sed -i 's/CREATE DATABASE \/\*!32312 IF NOT EXISTS\*\/ `edxapp` \/\*!40100 DEFAULT CHARACTER SET utf8 \*\/;/CREATE DATABASE \/\*!32312 IF NOT EXISTS\*\/ `openedx` \/\*!40100 DEFAULT CHARACTER SET utf8 \*\/;/' "$output_file"
    sed -i 's/USE `edxapp`;/USE `openedx`;/g' "$output_file"
    
    # Clean up
    rm "$temp_file"
    
    echo "Extraction and modification complete: $output_file"
}

# Find SQL files in current directory
sql_files=(*.sql)

if [ ${#sql_files[@]} -eq 0 ]; then
    echo "No SQL files found in current directory!"
    exit 1
fi

# List found SQL files
echo "Found SQL files:"
for i in "${!sql_files[@]}"; do
    echo "$((i+1)). ${sql_files[$i]}"
done

# Prompt user to select file
while true; do
    read -p "Enter the number of the MySQL dump file to process (1-${#sql_files[@]}): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#sql_files[@]}" ]; then
        selected_file="${sql_files[$((selection-1))]}"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# Confirm selection
read -p "You selected '${selected_file}'. Is this correct? (y/n): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Extract and modify both databases
extract_and_modify_database "$selected_file" "edxapp"
extract_and_modify_database "$selected_file" "edxapp_csmh"

echo "Processing complete! Created:"
echo "- edxapp_dump.sql"
echo "- edxapp_csmh_dump.sql"