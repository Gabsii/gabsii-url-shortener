#!/bin/bash

set -e
set -o pipefail

# Define the backup path
BACKUP_PATH="/data/url-shortener/backup"
COMPOSE_FILE="/data/url-shortener/docker-compose.yml"

# Function to check if a Docker container is running
container_exists() {
    docker-compose -f "$COMPOSE_FILE" ps | grep -q "$1"
}

# Function to find dump.rdb file in Redis container
find_dump_rdb() {
    docker-compose -f "$COMPOSE_FILE" exec -T redis sh -c "find /data -name dump.rdb"
}

# Step 1: Create a pre-deployment Redis backup
if container_exists "redis"; then
    echo "Creating a pre-deployment Redis backup..."

    # Issue SAVE command to persist the data to disk
    docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli SAVE

    # Wait for the SAVE operation to complete
    sleep 5

    # Find the dump.rdb file location
    DUMP_PATH=$(find_dump_rdb)

    if [ -z "$DUMP_PATH" ]; then
        echo "Error: dump.rdb file not found in Redis container."
        exit 1
    else
        echo "dump.rdb found at: $DUMP_PATH"
    fi

    # Ensure the backup directory exists on the host
    mkdir -p "$BACKUP_PATH"

    # Copy the dump.rdb file directly from the Redis container to the host machine
    REDIS_CONTAINER_ID=$(docker-compose -f "$COMPOSE_FILE" ps -q redis)
    docker cp "$REDIS_CONTAINER_ID:$DUMP_PATH" "$BACKUP_PATH/pre_deploy_$(date +%Y%m%d_%H%M%S).rdb"

else
    echo "Redis container not found. Skipping backup."
fi

# Step 2: Pull the latest images and redeploy the services
echo "Pulling the latest Docker images..."
docker-compose -f "$COMPOSE_FILE" pull

echo "Rebuilding and restarting the services..."
docker-compose -f "$COMPOSE_FILE" up --detach --build

# Step 3: Verify Redis data after deployment
echo "Waiting for Redis to start up..."
sleep 10

KEYS_COUNT=$(docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli DBSIZE)
echo "Redis has $KEYS_COUNT keys after deployment"

if [ "$KEYS_COUNT" -eq "0" ]; then
    echo "Warning: Redis appears to be empty. Restoring from backup..."
    exit 1
else
    echo "Redis data verification successful."
fi
