#!/bin/bash
# Verify Matrix deployment is working correctly

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SUCCESS=0
FAILURES=0

print_check() {
    local status=$1
    local message=$2
    local detail=$3

    if [ "$status" = "ok" ]; then
        echo -e "${GREEN}✓${NC} $message"
        [ -n "$detail" ] && echo -e "  ${CYAN}$detail${NC}"
        ((SUCCESS++))
    else
        echo -e "${RED}✗${NC} $message"
        [ -n "$detail" ] && echo -e "  ${RED}$detail${NC}"
        ((FAILURES++))
    fi
}

echo -e "${CYAN}Verifying Matrix deployment...${NC}"
echo ""

# Load environment variables
if [ -f ".env" ]; then
    source .env
fi

# Check container status
echo -e "${CYAN}Checking container status...${NC}"

check_container() {
    local container=$1
    local name=$2

    if docker compose ps | grep -q "$container.*Up"; then
        print_check "ok" "$name is running"
    else
        print_check "fail" "$name is not running" "Run: docker compose up -d"
    fi
}

check_container "postgres" "PostgreSQL"
check_container "synapse" "Synapse"
check_container "mas" "Matrix Authentication Service"
check_container "element" "Element Web"
check_container "element-admin" "Element Admin"

echo ""

# Check PostgreSQL connectivity
echo -e "${CYAN}Checking PostgreSQL...${NC}"
if docker compose exec -T postgres pg_isready -U synapse &> /dev/null; then
    print_check "ok" "PostgreSQL is accepting connections"
else
    print_check "fail" "PostgreSQL is not ready"
fi

echo ""

# Check Synapse API
echo -e "${CYAN}Checking Synapse API...${NC}"
if [ -n "$MATRIX_DOMAIN" ] && [ "$MATRIX_DOMAIN" != "CHANGE_ME" ]; then
    if curl -sf "https://$MATRIX_DOMAIN/_matrix/client/versions" > /dev/null 2>&1; then
        print_check "ok" "Synapse API is responding" "https://$MATRIX_DOMAIN/_matrix/client/versions"
    else
        # Try localhost as fallback
        if curl -sf "http://localhost:8008/_matrix/client/versions" > /dev/null 2>&1; then
            print_check "ok" "Synapse API is responding (localhost)" "http://localhost:8008/_matrix/client/versions"
        else
            print_check "fail" "Synapse API is not responding" "Check Caddy/proxy configuration"
        fi
    fi
else
    # Try localhost
    if curl -sf "http://localhost:8008/_matrix/client/versions" > /dev/null 2>&1; then
        print_check "ok" "Synapse API is responding (localhost)" "http://localhost:8008/_matrix/client/versions"
    else
        print_check "fail" "Synapse API is not responding"
    fi
fi

echo ""

# Check MAS health
echo -e "${CYAN}Checking Matrix Authentication Service...${NC}"
if curl -sf "http://localhost:8080/health" > /dev/null 2>&1; then
    print_check "ok" "MAS health check passed" "http://localhost:8080/health"
else
    print_check "fail" "MAS health check failed" "Check: docker compose logs mas"
fi

echo ""

# Check Element Web
echo -e "${CYAN}Checking Element Web...${NC}"
if [ -n "$ELEMENT_DOMAIN" ] && [ "$ELEMENT_DOMAIN" != "CHANGE_ME" ]; then
    if curl -sf "https://$ELEMENT_DOMAIN/" > /dev/null 2>&1; then
        print_check "ok" "Element Web is accessible" "https://$ELEMENT_DOMAIN/"
    else
        # Try localhost as fallback
        if curl -sf "http://localhost:8082/" > /dev/null 2>&1; then
            print_check "ok" "Element Web is running (localhost)" "http://localhost:8082/"
        else
            print_check "fail" "Element Web is not accessible"
        fi
    fi
else
    # Try localhost
    if curl -sf "http://localhost:8082/" > /dev/null 2>&1; then
        print_check "ok" "Element Web is running (localhost)" "http://localhost:8082/"
    else
        print_check "fail" "Element Web is not running"
    fi
fi

echo ""

# Check Element Admin
echo -e "${CYAN}Checking Element Admin...${NC}"
if curl -sf "http://localhost:8081/" > /dev/null 2>&1; then
    print_check "ok" "Element Admin is running" "http://localhost:8081/"
else
    print_check "fail" "Element Admin is not running"
fi

echo ""

# Check for common errors in logs
echo -e "${CYAN}Checking for errors in logs...${NC}"
ERROR_COUNT=$(docker compose logs --tail=100 2>&1 | grep -i "error" | grep -v "loglevel" | wc -l)
if [ "$ERROR_COUNT" -eq 0 ]; then
    print_check "ok" "No errors found in recent logs"
else
    print_check "fail" "Found $ERROR_COUNT error messages in logs" "Review: docker compose logs | grep -i error"
fi

echo ""

# Check database connectivity from Synapse
echo -e "${CYAN}Checking database connectivity...${NC}"
if docker compose logs synapse --tail=50 | grep -qi "database.*error\|could not connect"; then
    print_check "fail" "Synapse database connection errors detected" "Check logs: docker compose logs synapse"
else
    print_check "ok" "No database connection errors in Synapse logs"
fi

echo ""

# Summary
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}Verification Summary:${NC}"
echo -e "  ${GREEN}✓ Passed: $SUCCESS${NC}"
echo -e "  ${RED}✗ Failed: $FAILURES${NC}"
echo -e "${CYAN}============================================${NC}"

echo ""

if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}✓ All verification checks passed!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Create admin user: ${CYAN}make create-admin${NC}"
    echo -e "  2. Access Element: ${CYAN}https://$ELEMENT_DOMAIN${NC}"
    echo -e "  3. Access Admin: ${CYAN}http://localhost:8081${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some verification checks failed${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo -e "  1. Check service logs: ${CYAN}make logs${NC}"
    echo -e "  2. Check service status: ${CYAN}make status${NC}"
    echo -e "  3. Restart services: ${CYAN}make restart${NC}"
    echo "  4. Review SETUP.md troubleshooting section"
    echo ""
    exit 1
fi
