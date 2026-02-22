#!/bin/bash
# Wait for PostgreSQL to be ready

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

MAX_RETRIES=30
RETRY_INTERVAL=2
RETRY_COUNT=0

echo -e "${CYAN}Waiting for PostgreSQL to be ready...${NC}"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker compose exec -T postgres pg_isready -U synapse &> /dev/null; then
        echo -e "${GREEN}✓ PostgreSQL is ready!${NC}"
        exit 0
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))

    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo -e "${YELLOW}⏳ PostgreSQL not ready yet, waiting... (attempt $RETRY_COUNT/$MAX_RETRIES)${NC}"
        sleep $RETRY_INTERVAL
    fi
done

echo -e "${RED}✗ Timed out waiting for PostgreSQL${NC}"
echo -e "${YELLOW}Check logs: docker compose logs postgres${NC}"
exit 1
