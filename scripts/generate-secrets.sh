#!/bin/bash
# Generate all required secrets for Matrix setup

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

OUTPUT_FILE="secrets.env"

echo -e "${CYAN}Generating all required secrets...${NC}"
echo ""

# Create/overwrite secrets file
cat > "$OUTPUT_FILE" << 'EOF'
# Matrix Server Secrets
# Generated on: DATE_PLACEHOLDER
#
# IMPORTANT: Keep this file secure! Add it to .gitignore
# Copy these values to your .env file
#
# ⚠️  DO NOT commit this file to version control!

EOF

# Replace date placeholder
sed -i "s/DATE_PLACEHOLDER/$(date '+%Y-%m-%d %H:%M:%S')/" "$OUTPUT_FILE"

# 1. PostgreSQL Password
echo -e "${CYAN}Generating PostgreSQL password...${NC}"
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-32)
echo "POSTGRES_PASSWORD=\"$POSTGRES_PASSWORD\"" >> "$OUTPUT_FILE"
echo -e "${GREEN}✓${NC} PostgreSQL password generated"

# 2. Synapse Registration Secret
echo -e "${CYAN}Generating Synapse registration secret...${NC}"
SYNAPSE_REGISTRATION_SECRET=$(openssl rand -base64 32 | tr -d "=+/")
echo "SYNAPSE_REGISTRATION_SHARED_SECRET=\"$SYNAPSE_REGISTRATION_SECRET\"" >> "$OUTPUT_FILE"
echo -e "${GREEN}✓${NC} Synapse registration secret generated"

# 3. MAS Encryption Secret (must be exactly 64 hex characters)
echo -e "${CYAN}Generating MAS encryption secret...${NC}"
MAS_ENCRYPTION=$(openssl rand -hex 32)
echo "MAS_SECRETS_ENCRYPTION=\"$MAS_ENCRYPTION\"" >> "$OUTPUT_FILE"
echo -e "${GREEN}✓${NC} MAS encryption secret generated (64 hex chars)"

# 4. MAS Signing Key (EC private key for MAS v1.8.0+)
echo -e "${CYAN}Generating MAS signing key (EC private key)...${NC}"
MAS_EC_KEY=$(openssl ecparam -name prime256v1 -genkey)

# Add EC key section to file
cat >> "$OUTPUT_FILE" << 'EOF'

# MAS EC Private Key (for MAS v1.8.0+)
# This key should be pasted into mas/config/config.yaml in the secrets.keys section
# Format in YAML:
#   secrets:
#     keys:
#       - kid: "UNIQUE_KEY_ID"
#         key: |
#           -----BEGIN EC PRIVATE KEY-----
#           ... (paste the lines below, excluding the BEGIN/END markers) ...
#           -----END EC PRIVATE KEY-----
#
MAS_EC_PRIVATE_KEY="
EOF

echo "$MAS_EC_KEY" >> "$OUTPUT_FILE"
echo '"' >> "$OUTPUT_FILE"

echo -e "${GREEN}✓${NC} MAS EC signing key generated"

# 5. Authelia Client Secret (optional)
echo -e "${CYAN}Generating Authelia OIDC client secret (optional)...${NC}"
AUTHELIA_SECRET=$(openssl rand -base64 32 | tr -d "=+/")
echo "" >> "$OUTPUT_FILE"
echo "# Optional: Only needed if using Authelia for upstream OIDC" >> "$OUTPUT_FILE"
echo "AUTHELIA_CLIENT_SECRET=\"$AUTHELIA_SECRET\"" >> "$OUTPUT_FILE"
echo -e "${GREEN}✓${NC} Authelia client secret generated"

echo ""
echo -e "${GREEN}✓ All secrets generated successfully!${NC}"
echo ""
echo -e "${YELLOW}Secrets saved to: ${CYAN}$OUTPUT_FILE${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Copy the secrets from $OUTPUT_FILE to your .env file"
echo "  2. Add $OUTPUT_FILE to .gitignore (if not already)"
echo "  3. Store $OUTPUT_FILE in a secure password manager"
echo "  4. Extract the MAS EC key and add it to mas/config/config.yaml"
echo ""
echo -e "${RED}⚠️  IMPORTANT: Keep these secrets secure and never commit them to version control!${NC}"

# Add to .gitignore if not already present
if [ -f ".gitignore" ]; then
    if ! grep -q "secrets.env" .gitignore; then
        echo "secrets.env" >> .gitignore
        echo -e "${GREEN}✓${NC} Added secrets.env to .gitignore"
    fi
else
    echo "secrets.env" > .gitignore
    echo -e "${GREEN}✓${NC} Created .gitignore with secrets.env"
fi

# Set restrictive permissions on secrets file
chmod 600 "$OUTPUT_FILE"
echo -e "${GREEN}✓${NC} Set restrictive permissions on $OUTPUT_FILE (600)"
