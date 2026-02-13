#!/bin/bash

# Plumber Update Script
# Updates your self-managed Plumber instance to the latest version.
#
# Usage:
#   ./scripts/update.sh
#
# This script:
#   1. Pulls the latest changes from the git repository
#   2. Syncs image tags from versions.env into .env
#   3. Restarts containers with the new images

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Ensure we're in the repository root
if [ ! -f compose.yml ] || [ ! -f versions.env ]; then
    echo -e "${RED}Error:${NC} This script must be run from the Plumber platform repository root."
    exit 1
fi

# Ensure .env exists
if [ ! -f .env ]; then
    echo -e "${RED}Error:${NC} .env file not found. Run ./install.sh first."
    exit 1
fi

echo ""
echo -e "${BOLD}Updating Plumber...${NC}"
echo "───────────────────────────────────────"

# Step 1: Pull latest changes
echo ""
echo "Pulling latest changes..."
git pull
echo -e "${GREEN}✓${NC} Repository updated"

# Step 2: Read new image tags from versions.env
echo ""
echo "Syncing image versions..."
source versions.env

if [ -z "${FRONTEND_IMAGE_TAG:-}" ] || [ -z "${BACKEND_IMAGE_TAG:-}" ]; then
    echo -e "${RED}Error:${NC} versions.env is missing image tags."
    exit 1
fi

# Update or append FRONTEND_IMAGE_TAG in .env
if grep -q "^FRONTEND_IMAGE_TAG=" .env 2>/dev/null; then
    sed -i."" "s|^FRONTEND_IMAGE_TAG=.*|FRONTEND_IMAGE_TAG=${FRONTEND_IMAGE_TAG}|" .env
    rm -f .env."" 2>/dev/null || true
else
    echo "" >> .env
    echo "FRONTEND_IMAGE_TAG=${FRONTEND_IMAGE_TAG}" >> .env
fi

# Update or append BACKEND_IMAGE_TAG in .env
if grep -q "^BACKEND_IMAGE_TAG=" .env 2>/dev/null; then
    sed -i."" "s|^BACKEND_IMAGE_TAG=.*|BACKEND_IMAGE_TAG=${BACKEND_IMAGE_TAG}|" .env
    rm -f .env."" 2>/dev/null || true
else
    echo "BACKEND_IMAGE_TAG=${BACKEND_IMAGE_TAG}" >> .env
fi

# Ensure COMPOSE_PROFILES is set (migration for users upgrading from old format)
if ! grep -q "^COMPOSE_PROFILES=" .env 2>/dev/null; then
    echo -e "${YELLOW}!${NC} COMPOSE_PROFILES not found in .env, adding default (letsencrypt,internal-db)"
    echo "" >> .env
    echo "COMPOSE_PROFILES=letsencrypt,internal-db" >> .env
fi

echo -e "${GREEN}✓${NC} Frontend: ${FRONTEND_IMAGE_TAG}"
echo -e "${GREEN}✓${NC} Backend:  ${BACKEND_IMAGE_TAG}"

# Step 3: Restart containers
echo ""
echo "Restarting containers..."
docker compose up -d

echo ""
echo -e "${GREEN}✓ Plumber has been updated successfully!${NC}"
echo ""
