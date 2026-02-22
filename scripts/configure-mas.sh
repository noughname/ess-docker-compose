#!/bin/bash
# Configure Matrix Authentication Service (MAS)

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

MAS_CONFIG_DIR="mas/config"
MAS_CONFIG_FILE="$MAS_CONFIG_DIR/config.yaml"
TEMPLATE_FILE="templates/mas-config.yaml"

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Load environment variables
source .env

# Check if template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}✗ Template file not found: $TEMPLATE_FILE${NC}"
    exit 1
fi

echo -e "${CYAN}Configuring Matrix Authentication Service...${NC}"

# Create config directory
mkdir -p "$MAS_CONFIG_DIR"
echo -e "${GREEN}✓${NC} Created config directory"

# Check required variables
MISSING_VARS=0

check_var() {
    local var_name=$1
    local var_value=${!var_name}

    if [ -z "$var_value" ] || [ "$var_value" = "CHANGE_ME" ]; then
        echo -e "${RED}✗${NC} $var_name is not set in .env"
        MISSING_VARS=1
    fi
}

check_var "MATRIX_DOMAIN"
check_var "POSTGRES_PASSWORD"
check_var "MAS_SECRETS_ENCRYPTION"

if [ $MISSING_VARS -eq 1 ]; then
    echo -e "${RED}Please set all required variables in .env${NC}"
    exit 1
fi

# Verify MAS_SECRETS_ENCRYPTION is 64 hex characters
if [ ${#MAS_SECRETS_ENCRYPTION} -ne 64 ]; then
    echo -e "${RED}✗ MAS_SECRETS_ENCRYPTION must be exactly 64 hex characters${NC}"
    echo -e "${YELLOW}Current length: ${#MAS_SECRETS_ENCRYPTION}${NC}"
    echo -e "${YELLOW}Generate new: openssl rand -hex 32${NC}"
    exit 1
fi

# Copy template to config file
cp "$TEMPLATE_FILE" "$MAS_CONFIG_FILE"
echo -e "${GREEN}✓${NC} Copied template to $MAS_CONFIG_FILE"

# Replace placeholders
echo -e "${CYAN}Replacing configuration placeholders...${NC}"

# Use sed to replace placeholders
sed -i "s|{{MATRIX_DOMAIN}}|$MATRIX_DOMAIN|g" "$MAS_CONFIG_FILE"
sed -i "s|{{POSTGRES_PASSWORD}}|$POSTGRES_PASSWORD|g" "$MAS_CONFIG_FILE"
sed -i "s|{{MAS_SECRETS_ENCRYPTION}}|$MAS_SECRETS_ENCRYPTION|g" "$MAS_CONFIG_FILE"

echo -e "${GREEN}✓${NC} Replaced basic placeholders"

# Handle optional Authelia configuration
if [ -n "$AUTHELIA_CLIENT_SECRET" ] && [ "$AUTHELIA_CLIENT_SECRET" != "CHANGE_ME" ]; then
    if [ -n "$AUTHELIA_URL" ] && [ "$AUTHELIA_URL" != "CHANGE_ME" ]; then
        echo -e "${CYAN}Configuring Authelia OIDC integration...${NC}"

        # Replace Authelia placeholders
        sed -i "s|{{AUTHELIA_URL}}|$AUTHELIA_URL|g" "$MAS_CONFIG_FILE"
        sed -i "s|{{AUTHELIA_CLIENT_ID}}|${AUTHELIA_CLIENT_ID:-matrix_mas}|g" "$MAS_CONFIG_FILE"
        sed -i "s|{{AUTHELIA_CLIENT_SECRET}}|$AUTHELIA_CLIENT_SECRET|g" "$MAS_CONFIG_FILE"

        echo -e "${GREEN}✓${NC} Configured Authelia OIDC"
    else
        echo -e "${YELLOW}⚠${NC} Authelia client secret set but AUTHELIA_URL is not"
        echo -e "${YELLOW}  Skipping Authelia configuration${NC}"
    fi
else
    echo -e "${YELLOW}⚠${NC} Authelia not configured (optional)"
fi

# Check for remaining placeholders
REMAINING=$(grep -c "{{.*}}" "$MAS_CONFIG_FILE" || true)
if [ "$REMAINING" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} Warning: $REMAINING placeholder(s) remaining in config"
    echo -e "${YELLOW}  You may need to manually edit $MAS_CONFIG_FILE${NC}"
    grep "{{.*}}" "$MAS_CONFIG_FILE" | sed 's/^/  /'
fi

# Check for MAS EC key placeholder
if grep -q "{{MAS_EC_PRIVATE_KEY}}" "$MAS_CONFIG_FILE"; then
    echo ""
    echo -e "${YELLOW}⚠${NC} MAS EC private key placeholder found"
    echo -e "${YELLOW}  This must be replaced manually with your EC private key${NC}"
    echo ""
    echo -e "${CYAN}To add the EC key:${NC}"
    echo "  1. Look for MAS_EC_PRIVATE_KEY in secrets.env"
    echo "  2. Edit $MAS_CONFIG_FILE"
    echo "  3. Find the 'secrets:' section and 'keys:' subsection"
    echo "  4. Replace {{MAS_EC_PRIVATE_KEY}} with the key content"
    echo "  5. Format should be:"
    echo "     secrets:"
    echo "       keys:"
    echo "         - kid: \"key-$(date +%Y%m%d)\""
    echo "           key: |"
    echo "             -----BEGIN EC PRIVATE KEY-----"
    echo "             (paste key content here)"
    echo "             -----END EC PRIVATE KEY-----"
    echo ""
fi

# Verify database password matches
if grep -q "password: $POSTGRES_PASSWORD" "$MAS_CONFIG_FILE"; then
    echo -e "${GREEN}✓${NC} Database password matches .env"
else
    echo -e "${YELLOW}⚠${NC} Warning: Could not verify database password in config"
fi

echo ""
echo -e "${GREEN}✓ MAS configuration complete!${NC}"
echo -e "${YELLOW}Config file: $MAS_CONFIG_FILE${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review the configuration file"
echo "  2. Add EC private key if not already done"
echo -e "  3. Run: ${CYAN}make deploy${NC}"
