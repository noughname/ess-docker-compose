#!/bin/bash
# Configure Synapse database settings in homeserver.yaml

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

HOMESERVER_FILE="synapse/data/homeserver.yaml"

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Load environment variables
source .env

# Check if homeserver.yaml exists
if [ ! -f "$HOMESERVER_FILE" ]; then
    echo -e "${RED}✗ $HOMESERVER_FILE not found${NC}"
    echo -e "${YELLOW}Run 'make generate-synapse-config' first${NC}"
    exit 1
fi

# Check if POSTGRES_PASSWORD is set
if [ -z "$POSTGRES_PASSWORD" ] || [ "$POSTGRES_PASSWORD" = "CHANGE_ME" ]; then
    echo -e "${RED}✗ POSTGRES_PASSWORD not set in .env${NC}"
    exit 1
fi

echo -e "${CYAN}Configuring Synapse database settings...${NC}"

# Backup original file - handle permission issues
BACKUP_FILE="${HOMESERVER_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
if cp "$HOMESERVER_FILE" "$BACKUP_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Created backup of homeserver.yaml"
else
    # Try to backup to a different location if permission denied
    BACKUP_FILE="backups/homeserver.yaml.backup.$(date +%Y%m%d-%H%M%S)"
    mkdir -p backups
    if cp "$HOMESERVER_FILE" "$BACKUP_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Created backup in backups/ directory"
    else
        echo -e "${YELLOW}⚠${NC} Warning: Could not create backup (permission denied)"
        echo -e "${YELLOW}  Continuing without backup...${NC}"
    fi
fi

# Create a temporary Python script to update the YAML
cat > /tmp/update_synapse_db.py << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
import sys
import re

def update_database_config(file_path, password):
    with open(file_path, 'r') as f:
        content = f.read()

    # Database configuration to insert
    db_config = f"""database:
  name: psycopg2
  args:
    user: synapse
    password: {password}
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10
"""

    # Try to find and replace existing database section
    # Match from "database:" to the next top-level key (non-indented line)
    pattern = r'database:.*?(?=\n[a-z_]+:|$)'

    if re.search(pattern, content, re.DOTALL):
        # Replace existing database section
        content = re.sub(pattern, db_config.rstrip(), content, flags=re.DOTALL)
        print("Updated existing database configuration", file=sys.stderr)
    else:
        print("Warning: Could not find database section to replace", file=sys.stderr)
        return False

    with open(file_path, 'w') as f:
        f.write(content)

    return True

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: update_synapse_db.py <homeserver.yaml> <password>", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]
    password = sys.argv[2]

    if update_database_config(file_path, password):
        print("Successfully updated database configuration", file=sys.stderr)
        sys.exit(0)
    else:
        sys.exit(1)
PYTHON_SCRIPT

# Run the Python script
if sudo python3 /tmp/update_synapse_db.py "$HOMESERVER_FILE" "$POSTGRES_PASSWORD"; then
    echo -e "${GREEN}✓${NC} Updated database configuration in homeserver.yaml"
else
    echo -e "${RED}✗${NC} Failed to update database configuration"
    echo -e "${YELLOW}You may need to manually edit $HOMESERVER_FILE${NC}"
    rm /tmp/update_synapse_db.py
    exit 1
fi

# Clean up
rm /tmp/update_synapse_db.py

# Verify the configuration
if grep -q "name: psycopg2" "$HOMESERVER_FILE"; then
    echo -e "${GREEN}✓${NC} Verified: PostgreSQL configuration is present"
else
    echo -e "${YELLOW}⚠${NC} Warning: Could not verify PostgreSQL configuration"
fi

if grep -q "host: postgres" "$HOMESERVER_FILE"; then
    echo -e "${GREEN}✓${NC} Verified: PostgreSQL host is set correctly"
else
    echo -e "${YELLOW}⚠${NC} Warning: Could not verify PostgreSQL host"
fi

echo ""
echo -e "${GREEN}✓ Synapse database configuration complete!${NC}"
echo -e "${YELLOW}Backup saved to: ${HOMESERVER_FILE}.backup.*${NC}"
