#!/bin/bash
# Check prerequisites for Matrix setup

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SUCCESS=0
WARNINGS=0
FAILURES=0

print_check() {
    local status=$1
    local message=$2
    local detail=$3

    if [ "$status" = "ok" ]; then
        echo -e "${GREEN}✓${NC} $message"
        [ -n "$detail" ] && echo -e "  ${CYAN}$detail${NC}"
        ((SUCCESS++))
    elif [ "$status" = "warn" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
        [ -n "$detail" ] && echo -e "  ${YELLOW}$detail${NC}"
        ((WARNINGS++))
    else
        echo -e "${RED}✗${NC} $message"
        [ -n "$detail" ] && echo -e "  ${RED}$detail${NC}"
        ((FAILURES++))
    fi
}

echo -e "${CYAN}Checking prerequisites for Matrix setup...${NC}"
echo ""

# Check Docker
echo -e "${CYAN}Checking Docker...${NC}"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d ' ' -f3 | tr -d ',')
    print_check "ok" "Docker is installed" "Version: $DOCKER_VERSION"

    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        print_check "ok" "Docker daemon is running"
    else
        print_check "fail" "Docker daemon is not running" "Try: sudo systemctl start docker"
    fi

    # Check Docker permissions
    if docker ps &> /dev/null; then
        print_check "ok" "Docker permissions are correct"
    else
        print_check "warn" "Cannot run Docker without sudo" "Add user to docker group: sudo usermod -aG docker \$USER"
    fi
else
    print_check "fail" "Docker is not installed" "Install from: https://docs.docker.com/get-docker/"
fi

echo ""

# Check Docker Compose
echo -e "${CYAN}Checking Docker Compose...${NC}"
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version | cut -d ' ' -f4)
    print_check "ok" "Docker Compose (plugin) is installed" "Version: $COMPOSE_VERSION"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version | cut -d ' ' -f4 | tr -d ',')
    print_check "warn" "Using legacy docker-compose" "Version: $COMPOSE_VERSION (consider upgrading to docker compose plugin)"
else
    print_check "fail" "Docker Compose is not installed" "Install from: https://docs.docker.com/compose/install/"
fi

echo ""

# Check required commands
echo -e "${CYAN}Checking required commands...${NC}"

if command -v openssl &> /dev/null; then
    OPENSSL_VERSION=$(openssl version | cut -d ' ' -f2)
    print_check "ok" "OpenSSL is installed" "Version: $OPENSSL_VERSION"
else
    print_check "fail" "OpenSSL is not installed" "Install: sudo apt-get install openssl"
fi

if command -v curl &> /dev/null; then
    CURL_VERSION=$(curl --version | head -n1 | cut -d ' ' -f2)
    print_check "ok" "curl is installed" "Version: $CURL_VERSION"
else
    print_check "fail" "curl is not installed" "Install: sudo apt-get install curl"
fi

if command -v jq &> /dev/null; then
    JQ_VERSION=$(jq --version | cut -d '-' -f2)
    print_check "ok" "jq is installed" "Version: $JQ_VERSION"
else
    print_check "warn" "jq is not installed" "Optional but recommended for JSON parsing. Install: sudo apt-get install jq"
fi

echo ""

# Check ports availability
echo -e "${CYAN}Checking port availability...${NC}"

check_port() {
    local port=$1
    local service=$2
    if ! command -v netstat &> /dev/null && ! command -v ss &> /dev/null; then
        print_check "warn" "Cannot check port $port ($service)" "netstat/ss not available"
        return
    fi

    if command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":$port "; then
            print_check "warn" "Port $port is already in use ($service)" "May conflict with deployment"
        else
            print_check "ok" "Port $port is available ($service)"
        fi
    elif netstat -tuln 2>/dev/null | grep -q ":$port "; then
        print_check "warn" "Port $port is already in use ($service)" "May conflict with deployment"
    else
        print_check "ok" "Port $port is available ($service)"
    fi
}

check_port 8008 "Synapse"
check_port 8080 "MAS"
check_port 8081 "Element Admin"
check_port 8082 "Element Web"
check_port 5432 "PostgreSQL"

echo ""

# Check disk space
echo -e "${CYAN}Checking disk space...${NC}"
AVAILABLE_GB=$(df -BG . | tail -1 | awk '{print $4}' | tr -d 'G')
if [ "$AVAILABLE_GB" -gt 10 ]; then
    print_check "ok" "Sufficient disk space available" "${AVAILABLE_GB}GB free"
elif [ "$AVAILABLE_GB" -gt 5 ]; then
    print_check "warn" "Limited disk space" "${AVAILABLE_GB}GB free (recommend >10GB)"
else
    print_check "fail" "Insufficient disk space" "${AVAILABLE_GB}GB free (need at least 5GB)"
fi

echo ""

# Check if .env exists
echo -e "${CYAN}Checking configuration files...${NC}"
if [ -f ".env" ]; then
    print_check "ok" ".env file exists"

    # Check for placeholder values
    if grep -q "CHANGE_ME" .env 2>/dev/null; then
        print_check "warn" ".env contains CHANGE_ME placeholders" "Update with actual values"
    fi
else
    print_check "warn" ".env file not found" "Run: make setup-env"
fi

if [ -f "docker-compose.yml" ]; then
    print_check "ok" "docker-compose.yml exists"
else
    print_check "fail" "docker-compose.yml not found" "Are you in the correct directory?"
fi

if [ -d "templates" ]; then
    print_check "ok" "templates directory exists"
else
    print_check "warn" "templates directory not found" "Some setup steps may fail"
fi

echo ""

# Summary
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}Summary:${NC}"
echo -e "  ${GREEN}✓ Passed: $SUCCESS${NC}"
echo -e "  ${YELLOW}⚠ Warnings: $WARNINGS${NC}"
echo -e "  ${RED}✗ Failed: $FAILURES${NC}"
echo -e "${CYAN}============================================${NC}"

echo ""

if [ $FAILURES -gt 0 ]; then
    echo -e "${RED}✗ Prerequisites check failed!${NC}"
    echo -e "${YELLOW}Please resolve the failed checks before continuing.${NC}"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ Prerequisites check passed with warnings${NC}"
    echo -e "${YELLOW}Review the warnings above. You may continue, but some features may not work.${NC}"
    exit 0
else
    echo -e "${GREEN}✓ All prerequisites check passed!${NC}"
    echo -e "${CYAN}You're ready to proceed with setup.${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. make setup-env"
    echo "  2. make generate-secrets"
    echo "  3. Update .env with generated secrets"
    echo "  4. make generate-synapse-config"
    exit 0
fi
