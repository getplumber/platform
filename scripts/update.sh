#!/bin/bash

# Plumber Update Script
# Updates your self-managed Plumber Platform to the version pinned in versions.env.
#
# Usage:
#   ./scripts/update.sh
#
# This script:
#   1. Stops running containers (using the current compose config)
#   2. Pulls the latest changes from the git repository
#   3. Syncs PLATFORM_VERSION from versions.env into .env (one pin for both images)
#   4. Rebuilds the custom CA bundle if you use one
#   5. Starts containers with the new images (the backend migrates the database on boot)
#
# Upgrades are sequential and additive: rolling back is reverting PLATFORM_VERSION
# in .env and starting again. Never downgrade the database by hand.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

if [ ! -f compose.yml ] || [ ! -f versions.env ]; then
    echo -e "${RED}Error:${NC} This script must be run from the Plumber platform repository root."
    exit 1
fi
if [ ! -f .env ]; then
    echo -e "${RED}Error:${NC} .env file not found. Run ./install.sh first."
    exit 1
fi

set_env_var() {
    local KEY="$1"
    local VALUE="$2"
    if grep -q "^${KEY}=" .env 2>/dev/null; then
        sed -i."" "s|^${KEY}=.*|${KEY}=${VALUE}|" .env
        rm -f .env."" 2>/dev/null || true
    else
        echo "${KEY}=${VALUE}" >> .env
    fi
}

if grep -q "^DOMAIN_NAME=" .env 2>/dev/null; then
    DEPLOY_TYPE="production"
    COMPOSE_CMD="docker compose"
else
    DEPLOY_TYPE="local"
    COMPOSE_CMD="docker compose -f compose.local.yml"
fi

echo ""
echo -e "${BOLD}Updating Plumber (${DEPLOY_TYPE})...${NC}"
echo "───────────────────────────────────────"

echo ""
echo "Stopping containers..."
$COMPOSE_CMD down --remove-orphans
echo -e "${GREEN}✓${NC} Containers stopped"

echo ""
echo "Pulling latest changes..."
git pull
echo -e "${GREEN}✓${NC} Repository updated"

echo ""
echo "Loading image version..."
set -a
# shellcheck disable=SC1091
source versions.env
set +a
if [ -z "${PLATFORM_VERSION:-}" ]; then
    echo -e "${RED}Error:${NC} versions.env is missing PLATFORM_VERSION."
    exit 1
fi
set_env_var "PLATFORM_VERSION" "${PLATFORM_VERSION}"
echo -e "${GREEN}✓${NC} Platform: ${PLATFORM_VERSION}"

echo ""
bash scripts/ca-bundle.sh

echo ""
echo "Starting containers..."
$COMPOSE_CMD up -d

echo ""
echo -e "${GREEN}✓ Plumber has been updated to ${PLATFORM_VERSION}!${NC}"
echo ""
