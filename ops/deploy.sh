#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.
set -o pipefail  # Return exit status of the last command in the pipeline that failed.

# Define the backup path
BACKUP_PATH="/data/url-shortener/backup"

# Function to check if a Docker container is running
container_exists() {
    docker-compose ps | grep -q "$1"
}

# Step 1: Create a pre-deployment Redis backup
if container_exists "redis"; then
    echo "Creating a pre-deployment Redis backup..."
    docker-compose exec -T redis redis-cli SAVE
    # Copy the dump.rdb file from the Docker volume to the backup directory on the host
    docker run --rm -v redis-data:/data -v "$BACKUP_PATH":/backup busybox cp /data/dump.rdb /backup/pre_deploy_$(date +%Y%m%d_%H%M%S).rdb
else
    echo "Redis container not found. Skipping backup."
fi

# Step 2: Pull the latest images and redeploy the services
echo "Pulling the latest Docker images..."
docker-compose pull

echo "Rebuilding and restarting the services..."
docker-compose up --detach --build

# Step 3: Verify Redis data after deployment
echo "Waiting for Redis to start up..."
sleep 10  # Give Redis time to start up

KEYS_COUNT=$(docker-compose exec -T redis redis-cli DBSIZE)
echo "Redis has $KEYS_COUNT keys after deployment"

if [ "$KEYS_COUNT" -eq "0" ]; then
    echo "Warning: Redis appears to be empty. Restoring from backup..."
    docker-compose down
    cp "$BACKUP_PATH/pre_deploy_*.rdb" /path/to/redis/data/dump.rdb
    docker-compose up -d
else
    echo "Redis data verification successful."
fi
