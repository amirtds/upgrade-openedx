#!/bin/bash

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
    ["redwood"]="18.2.2"
)

# Set environment variables
export LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data/"
export LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
export LOCAL_TUTOR_MYSQL_ROOT_USERNAME=$(tutor config printvalue MYSQL_ROOT_USERNAME)

# Add color variables at the top of the script
BLUE='\033[1;34m'
NC='\033[0m' # No Color

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

# 1. Export Quince DB
# -------------------------------
## Create export directory for Quince
EXPORT_DIR="quince_export"
echo -e "${BLUE}Creating export directory: $EXPORT_DIR${NC}"
mkdir -p "$EXPORT_DIR"

## Export MySQL databases
echo -e "${BLUE}Exporting MySQL databases...${NC}"
docker exec -i tutor_local-mysql-1 mysqldump -u root -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" --databases openedx > "$EXPORT_DIR/openedx.sql"

## Export MongoDB databases
echo -e "${BLUE}Exporting MongoDB databases...${NC}"
docker exec -i tutor_local-mongodb-1 mongodump --out=/data/db/dump/
docker exec -i tutor_local-mongodb-1 bash -c "cd /data/db/dump && tar czf /data/db/mongodb_dump.tar.gz ."
docker cp tutor_local-mongodb-1:/data/db/mongodb_dump.tar.gz "$EXPORT_DIR/"

echo -e "${BLUE}Export completed successfully!${NC}"
echo -e "${BLUE}Files are stored in: $EXPORT_DIR${NC}"


# 2. Install Redwood and import Quince DB
# -------------------------------

# Clean up Docker and Tutor
cleanup_docker
cleanup_tutor

## Install Redwood
sudo curl -L "https://github.com/overhangio/tutor/releases/download/v18.2.2/tutor-$(uname -s)_$(uname -m)" -o /usr/local/bin/tutor
sudo chmod 0755 /usr/local/bin/tutor

echo -e "${BLUE}Installing Tutor v18.2.2 (Redwood)...${NC}"
tutor local launch -I

echo -e "${BLUE}Tutor Redwood installation completed!${NC}"

# Set environment variables
export LOCAL_TUTOR_DATA_DIRECTORY="$(tutor config printroot)/data"
export LOCAL_TUTOR_MYSQL_ROOT_PASSWORD=$(tutor config printvalue MYSQL_ROOT_PASSWORD)
export LOCAL_TUTOR_MYSQL_ROOT_USERNAME=$(tutor config printvalue MYSQL_ROOT_USERNAME)


## Import Quince DB
echo -e "${BLUE}Importing Quince DB...${NC}"

# Copy MongoDB backup
echo -e "${BLUE}Copying MongoDB backup...${NC}"
MONGO_BACKUP_DIR="$LOCAL_TUTOR_DATA_DIRECTORY/mongodb/backup/"
sudo mkdir -p "$MONGO_BACKUP_DIR"
sudo cp -R "$EXPORT_DIR/mongodb_dump.tar.gz" "$MONGO_BACKUP_DIR"

# extract the mongodb_dump.tar.gz file
echo -e "${BLUE}Extracting MongoDB backup...${NC}"
sudo tar -xzf "$MONGO_BACKUP_DIR/mongodb_dump.tar.gz" -C "$MONGO_BACKUP_DIR"

# Restore MongoDB backups
echo -e "${BLUE}Restoring MongoDB backups...${NC}"
docker exec -i tutor_local-mongodb-1 sh -c 'exec mongorestore --drop -d openedx /data/db/backup/openedx/'
docker exec -i tutor_local-mongodb-1 sh -c 'exec mongorestore --drop -d cs_comments_service /data/db/backup/cs_comments_service/'

# Drop and restore MySQL database
echo -e "${BLUE}Restoring MySQL database...${NC}"
docker exec -i tutor_local-mysql-1 sh -c "exec mysql -u$LOCAL_TUTOR_MYSQL_ROOT_USERNAME -p$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD -e \"DROP DATABASE IF EXISTS openedx; CREATE DATABASE openedx;\""

# Set MySQL parameters before import
docker exec -i tutor_local-mysql-1 mysql \
    -u"$LOCAL_TUTOR_MYSQL_ROOT_USERNAME" \
    -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" \
    -e "SET GLOBAL max_allowed_packet=1073741824; \
        SET GLOBAL net_buffer_length=1048576; \
        SET GLOBAL innodb_buffer_pool_size=8589934592; \
        SET GLOBAL foreign_key_checks=0;"

# Import with progress bar
echo -e "${BLUE}Importing database (this may take a while)...${NC}"
pv -s $(stat --format=%s "$EXPORT_DIR/openedx.sql") "$EXPORT_DIR/openedx.sql" | docker exec -i tutor_local-mysql-1 mysql \
    -u"$LOCAL_TUTOR_MYSQL_ROOT_USERNAME" \
    -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" \
    --init-command="SET SESSION foreign_key_checks=0;" \
    openedx

# Reset MySQL parameters after import
docker exec -i tutor_local-mysql-1 mysql \
    -u"$LOCAL_TUTOR_MYSQL_ROOT_USERNAME" \
    -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" \
    -e "SET GLOBAL foreign_key_checks=1;"

# # Fake migrations
echo -e "${BLUE}Faking migrations...${NC}"
# tutor local run lms sh -c "python manage.py lms migrate integrated_channel 0030 --fake"
# tutor local run lms sh -c "python manage.py lms migrate badges 0005 --fake"
# tutor local run lms sh -c "python manage.py lms migrate enterprise 0200 --fake"

# Run remaining migrations
echo -e "${BLUE}Running migrations...${NC}"
tutor local run lms sh -c "python manage.py lms migrate"
tutor local run cms sh -c "python manage.py cms migrate"

# Create site configuration
echo "Creating site configuration..."
tutor local run lms sh -c "python manage.py lms shell -c \"
from django.contrib.sites.models import Site
from openedx.core.djangoapps.site_configuration.models import SiteConfiguration

# Create or get the site
site, _ = Site.objects.get_or_create(
    domain='thegymnasium.com',
    defaults={'name': 'The Gymnasium'}
)

# Create or update site configuration
config, _ = SiteConfiguration.objects.update_or_create(
    site=site,
    defaults={
        'enabled': True,
    }
)
print('Site configuration created/updated successfully')
\""

# Create Login Service Account
echo "${BLUE}Creating Login Service Account...${NC}"
tutor local run lms sh -c "python manage.py lms shell -c '
from django.contrib.auth import get_user_model
from oauth2_provider.models import Application
from django.conf import settings

User = get_user_model()

# Create login service user
username = \"login_service_user\"
email = username + \"@fake.email\"
user, created = User.objects.get_or_create(username=username, email=email)
if created:
    user.set_unusable_password()
    user.save()

# Create OAuth application
app, created = Application.objects.get_or_create(
    name=\"Login Service for JWT Cookies\",
    client_id=\"login_service_user\",
    user=user,
    defaults={
        \"client_type\": \"public\",
        \"authorization_grant_type\": \"password\",
        \"redirect_uris\": \"\",
        \"client_secret\": \"login_service_user\"
    }
)
print(\"Login service user and application created successfully\")
'"

# Create content type gating table
echo "${BLUE}Creating content type gating table...${NC}"
docker exec -i tutor_local-mysql-1 mysql \
    -u"$LOCAL_TUTOR_MYSQL_ROOT_USERNAME" \
    -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" \
    openedx << 'EOF'

CREATE TABLE IF NOT EXISTS content_type_gating_contenttypegatingconfig (
    id int(11) NOT NULL AUTO_INCREMENT,
    change_date datetime(6) NOT NULL,
    enabled tinyint(1) NOT NULL,
    enabled_as_of datetime(6) DEFAULT NULL,
    studio_override_enabled tinyint(1) NOT NULL,
    org varchar(255) DEFAULT NULL,
    org_course varchar(255) DEFAULT NULL,
    changed_by_id int(11) DEFAULT NULL,
    course_id varchar(255) DEFAULT NULL,
    site_id int(11) DEFAULT NULL,
    PRIMARY KEY (id),
    KEY content_type_gating_co_changed_by_id_e1754c4b_fk_auth_user_id (changed_by_id),
    KEY content_type_gating_co_site_id_c9f3bc6a_fk_django_si (site_id),
    KEY content_type_gating_contenttypegatingconfig_org_043e72a9 (org),
    KEY content_type_gating_contenttypegatingconfig_org_course_e0a64a09 (org_course),
    KEY content_type_gating_contenttypegatingconfig_course_id_f16cc868 (course_id),
    CONSTRAINT content_type_gating_co_changed_by_id_e1754c4b_fk_auth_user_id FOREIGN KEY (changed_by_id) REFERENCES auth_user (id),
    CONSTRAINT content_type_gating_co_site_id_c9f3bc6a_fk_django_si FOREIGN KEY (site_id) REFERENCES django_site (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

EOF

echo "${BLUE}Content type gating table created and configured successfully${NC}"

# Run additional CMS commands
echo -e "${BLUE}Running CMS commands...${NC}"
tutor local run cms sh -c "./manage.py cms reindex_course --all"
tutor local run cms sh -c "./manage.py cms simulate_publish"
tutor local run cms sh -c "./manage.py cms generate_course_overview --all-courses"

# Verify data restoration
echo -e "\n${BLUE}=== VERIFYING DATA RESTORATION ===${NC}"

# Get MySQL counts
mysql_status=0
user_count=$(docker exec -i tutor_local-mysql-1 mysql -u root -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM openedx.auth_user;" 2>/dev/null) || mysql_status=$?
course_count=$(docker exec -i tutor_local-mysql-1 mysql -u root -p"$LOCAL_TUTOR_MYSQL_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM openedx.course_overviews_courseoverview;" 2>/dev/null) || mysql_status=$?

# Get MongoDB counts
mongo_status=0
modulestore_count=$(docker exec -i tutor_local-mongodb-1 mongo openedx --quiet --eval "db.modulestore.active_versions.count()" 2>/dev/null) || mongo_status=$?
forum_count=$(docker exec -i tutor_local-mongodb-1 mongo cs_comments_service --quiet --eval "db.contents.count()" 2>/dev/null) || mongo_status=$?

# Display results
if [ $mysql_status -eq 0 ] && [ $mongo_status -eq 0 ]; then
    echo -e "\n${BLUE}✅ Database restoration completed successfully!${NC}"
    echo -e "${BLUE}MySQL Users: $user_count${NC}"
    echo -e "${BLUE}MySQL Courses: $course_count${NC}"
    echo -e "${BLUE}MongoDB Modulestore Items: $modulestore_count${NC}"
    echo -e "${BLUE}MongoDB Forum Items: $forum_count${NC}"
else
    echo -e "\n${BLUE}⚠️ Database restoration completed with warnings. Please verify the data manually.${NC}"
fi

echo -e "\n${BLUE}=== VERIFICATION COMPLETED ===${NC}\n"