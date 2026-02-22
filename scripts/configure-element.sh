#!/bin/bash
# Configure Element Web client

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

ELEMENT_CONFIG_DIR="element/config"
ELEMENT_CONFIG_FILE="$ELEMENT_CONFIG_DIR/config.json"
TEMPLATE_FILE="templates/element-config.json"

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

echo -e "${CYAN}Configuring Element Web...${NC}"

# Create config directory
mkdir -p "$ELEMENT_CONFIG_DIR"
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
check_var "ELEMENT_DOMAIN"

if [ $MISSING_VARS -eq 1 ]; then
    echo -e "${RED}Please set all required variables in .env${NC}"
    exit 1
fi

# Copy template to config file
cp "$TEMPLATE_FILE" "$ELEMENT_CONFIG_FILE"
echo -e "${GREEN}✓${NC} Copied template to $ELEMENT_CONFIG_FILE"

# Replace placeholders
echo -e "${CYAN}Replacing configuration placeholders...${NC}"

sed -i "s|{{MATRIX_DOMAIN}}|$MATRIX_DOMAIN|g" "$ELEMENT_CONFIG_FILE"
sed -i "s|{{ELEMENT_DOMAIN}}|$ELEMENT_DOMAIN|g" "$ELEMENT_CONFIG_FILE"

echo -e "${GREEN}✓${NC} Replaced placeholders"

# Check for remaining placeholders
REMAINING=$(grep -c "{{.*}}" "$ELEMENT_CONFIG_FILE" || true)
if [ "$REMAINING" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} Warning: $REMAINING placeholder(s) remaining in config"
    echo -e "${YELLOW}  You may need to manually edit $ELEMENT_CONFIG_FILE${NC}"
    grep "{{.*}}" "$ELEMENT_CONFIG_FILE" | sed 's/^/  /'
else
    echo -e "${GREEN}✓${NC} All placeholders replaced"
fi

# Verify JSON syntax
if command -v jq &> /dev/null; then
    if jq empty "$ELEMENT_CONFIG_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} JSON syntax is valid"
    else
        echo -e "${RED}✗${NC} JSON syntax error in config file"
        echo -e "${YELLOW}  Check $ELEMENT_CONFIG_FILE for syntax errors${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC} jq not installed, skipping JSON validation"
fi

echo ""
echo -e "${GREEN}✓ Element Web configuration complete!${NC}"
echo -e "${YELLOW}Config file: $ELEMENT_CONFIG_FILE${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review the configuration file"
echo -e "  2. Run: ${CYAN}make deploy${NC}"
echo -e "  3. Access Element at: ${CYAN}https://$ELEMENT_DOMAIN${NC}"
