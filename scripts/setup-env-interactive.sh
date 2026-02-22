#!/bin/bash
# Interactive environment setup - copies secrets and prompts for domains

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

ENV_FILE=".env"
SECRETS_FILE="secrets.env"
TEMPLATE_FILE="templates/.env.template"

echo -e "${CYAN}Interactive Environment Setup${NC}"
echo ""

# Check if template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}✗ Template file not found: $TEMPLATE_FILE${NC}"
    exit 1
fi

# Check if secrets.env exists
if [ ! -f "$SECRETS_FILE" ]; then
    echo -e "${RED}✗ secrets.env not found${NC}"
    echo -e "${YELLOW}Run 'make generate-secrets' first${NC}"
    exit 1
fi

# Backup existing .env if it exists
if [ -f "$ENV_FILE" ]; then
    BACKUP_FILE="${ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$ENV_FILE" "$BACKUP_FILE"
    echo -e "${YELLOW}⚠ Backing up existing .env to $BACKUP_FILE${NC}"
fi

# Copy template to .env
cp "$TEMPLATE_FILE" "$ENV_FILE"
echo -e "${GREEN}✓${NC} Created .env from template"

# Read secrets from secrets.env
echo -e "${CYAN}Loading secrets from $SECRETS_FILE...${NC}"

# Source the secrets file
source "$SECRETS_FILE"

# Update .env with secrets
echo -e "${CYAN}Copying secrets to .env...${NC}"

# Replace secrets in .env
if [ -n "$POSTGRES_PASSWORD" ]; then
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=\"$POSTGRES_PASSWORD\"/" "$ENV_FILE"
    echo -e "${GREEN}✓${NC} PostgreSQL password"
fi

if [ -n "$SYNAPSE_REGISTRATION_SHARED_SECRET" ]; then
    sed -i "s/SYNAPSE_REGISTRATION_SHARED_SECRET=.*/SYNAPSE_REGISTRATION_SHARED_SECRET=\"$SYNAPSE_REGISTRATION_SHARED_SECRET\"/" "$ENV_FILE"
    echo -e "${GREEN}✓${NC} Synapse registration secret"
fi

if [ -n "$MAS_SECRETS_ENCRYPTION" ]; then
    sed -i "s/MAS_SECRETS_ENCRYPTION=.*/MAS_SECRETS_ENCRYPTION=\"$MAS_SECRETS_ENCRYPTION\"/" "$ENV_FILE"
    echo -e "${GREEN}✓${NC} MAS encryption secret"
fi

if [ -n "$AUTHELIA_CLIENT_SECRET" ]; then
    sed -i "s/AUTHELIA_CLIENT_SECRET=.*/AUTHELIA_CLIENT_SECRET=\"$AUTHELIA_CLIENT_SECRET\"/" "$ENV_FILE"
    echo -e "${GREEN}✓${NC} Authelia client secret (optional)"
fi

echo ""
echo -e "${CYAN}Domain Configuration${NC}"
echo -e "${YELLOW}Enter your base domain (without subdomains)${NC}"
echo -e "${YELLOW}Examples:${NC}"
echo -e "  - ${CYAN}example.com${NC} → matrix.example.com, element.example.com"
echo -e "  - ${CYAN}some.example.com${NC} → matrix.some.example.com, element.some.example.com"
echo ""

# Prompt for base domain
while true; do
    read -p "Base domain: " BASE_DOMAIN
    if [ -n "$BASE_DOMAIN" ]; then
        # Remove any protocol if user included it
        BASE_DOMAIN=$(echo "$BASE_DOMAIN" | sed 's~^https\?://~~')
        # Remove trailing slash if present
        BASE_DOMAIN=$(echo "$BASE_DOMAIN" | sed 's~/$~~')
        # Remove leading 'matrix.' or 'element.' if user accidentally included them
        if [[ "$BASE_DOMAIN" =~ ^(matrix|element)\. ]]; then
            BASE_DOMAIN=$(echo "$BASE_DOMAIN" | sed 's~^[^.]*\.~~')
            echo -e "${YELLOW}  Removed subdomain prefix, using: ${CYAN}$BASE_DOMAIN${NC}"
        fi
        break
    else
        echo -e "${RED}Base domain cannot be empty${NC}"
    fi
done

# Generate subdomains
MATRIX_DOMAIN="matrix.$BASE_DOMAIN"
ELEMENT_DOMAIN="element.$BASE_DOMAIN"

echo ""
echo -e "${CYAN}Generated domains:${NC}"
echo -e "${GREEN}✓${NC} Matrix domain: ${CYAN}$MATRIX_DOMAIN${NC}"
echo -e "${GREEN}✓${NC} Element domain: ${CYAN}$ELEMENT_DOMAIN${NC}"
echo ""

# Ask if user wants to customize
read -p "Do you want to customize these domains? (y/N): " CUSTOMIZE_DOMAINS

if [[ "$CUSTOMIZE_DOMAINS" =~ ^[Yy]$ ]]; then
    echo ""
    # Prompt for MATRIX_DOMAIN
    read -p "Matrix server domain [$MATRIX_DOMAIN]: " CUSTOM_MATRIX
    if [ -n "$CUSTOM_MATRIX" ]; then
        MATRIX_DOMAIN=$(echo "$CUSTOM_MATRIX" | sed 's~^https\?://~~')
    fi

    # Prompt for ELEMENT_DOMAIN
    read -p "Element web domain [$ELEMENT_DOMAIN]: " CUSTOM_ELEMENT
    if [ -n "$CUSTOM_ELEMENT" ]; then
        ELEMENT_DOMAIN=$(echo "$CUSTOM_ELEMENT" | sed 's~^https\?://~~')
    fi

    echo ""
    echo -e "${GREEN}✓${NC} Using custom domains:"
    echo -e "  Matrix: ${CYAN}$MATRIX_DOMAIN${NC}"
    echo -e "  Element: ${CYAN}$ELEMENT_DOMAIN${NC}"
fi

# Update domains in .env
sed -i "s/MATRIX_DOMAIN=.*/MATRIX_DOMAIN=\"$MATRIX_DOMAIN\"/" "$ENV_FILE"
sed -i "s/ELEMENT_DOMAIN=.*/ELEMENT_DOMAIN=\"$ELEMENT_DOMAIN\"/" "$ENV_FILE"

# Ask about Authelia (optional)
echo ""
echo -e "${CYAN}Authelia OIDC Integration (Optional)${NC}"
read -p "Do you want to configure Authelia OIDC? (y/N): " USE_AUTHELIA

if [[ "$USE_AUTHELIA" =~ ^[Yy]$ ]]; then
    # Auto-generate Authelia URL from base domain
    AUTHELIA_URL="https://auth.$BASE_DOMAIN"
    sed -i "s|AUTHELIA_URL=.*|AUTHELIA_URL=\"$AUTHELIA_URL\"|" "$ENV_FILE"
    echo -e "${GREEN}✓${NC} Authelia URL: ${CYAN}$AUTHELIA_URL${NC}"

    read -p "Authelia Client ID (default: matrix_mas): " AUTHELIA_CLIENT_ID
    AUTHELIA_CLIENT_ID=${AUTHELIA_CLIENT_ID:-matrix_mas}
    sed -i "s/AUTHELIA_CLIENT_ID=.*/AUTHELIA_CLIENT_ID=\"$AUTHELIA_CLIENT_ID\"/" "$ENV_FILE"
    echo -e "${GREEN}✓${NC} Authelia Client ID: ${CYAN}$AUTHELIA_CLIENT_ID${NC}"
else
    echo -e "${YELLOW}⚠${NC} Skipping Authelia configuration"
fi

echo ""
echo -e "${GREEN}✓ Environment configuration complete!${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo -e "  • Secrets copied from $SECRETS_FILE"
echo -e "  • Matrix domain: ${CYAN}$MATRIX_DOMAIN${NC}"
echo -e "  • Element domain: ${CYAN}$ELEMENT_DOMAIN${NC}"
if [[ "$USE_AUTHELIA" =~ ^[Yy]$ ]]; then
    echo -e "  • Authelia URL: ${CYAN}https://auth.$BASE_DOMAIN${NC}"
fi
echo ""
echo -e "${YELLOW}Configuration saved to: ${CYAN}$ENV_FILE${NC}"
if [ -n "$BACKUP_FILE" ]; then
    echo -e "${YELLOW}Previous .env backed up to: ${CYAN}$BACKUP_FILE${NC}"
fi
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Review .env file: ${CYAN}cat .env${NC}"
echo -e "  2. Run: ${CYAN}make full-setup${NC}"
