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
#   3. Migrates old .env format if needed (auto-detects COMPOSE_PROFILES)
#   4. Restarts containers with the new images

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
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

# =============================================================================
# Helper: update or append a variable in .env
# =============================================================================
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

echo ""
echo -e "${BOLD}Updating Plumber...${NC}"
echo "───────────────────────────────────────"

# =============================================================================
# Step 1: Pull latest changes
# =============================================================================
echo ""
echo "Pulling latest changes..."
git pull
echo -e "${GREEN}✓${NC} Repository updated"

# =============================================================================
# Step 2: Sync image tags from versions.env
# =============================================================================
echo ""
echo "Syncing image versions..."
source versions.env

if [ -z "${FRONTEND_IMAGE_TAG:-}" ] || [ -z "${BACKEND_IMAGE_TAG:-}" ]; then
    echo -e "${RED}Error:${NC} versions.env is missing image tags."
    exit 1
fi

set_env_var "FRONTEND_IMAGE_TAG" "${FRONTEND_IMAGE_TAG}"
set_env_var "BACKEND_IMAGE_TAG" "${BACKEND_IMAGE_TAG}"

echo -e "${GREEN}✓${NC} Frontend: ${FRONTEND_IMAGE_TAG}"
echo -e "${GREEN}✓${NC} Backend:  ${BACKEND_IMAGE_TAG}"

# =============================================================================
# Step 3: Migrate COMPOSE_PROFILES if missing (old .env format)
# =============================================================================
if ! grep -q "^COMPOSE_PROFILES=" .env 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}Migration required:${NC} COMPOSE_PROFILES is not set in your .env file."
    echo ""
    echo -e "${DIM}Starting with this version, Plumber uses Docker Compose profiles instead of${NC}"
    echo -e "${DIM}separate compose files. Your .env needs a COMPOSE_PROFILES variable.${NC}"
    echo ""

    # Source .env to read current config for auto-detection
    set -a
    source .env
    set +a

    # --- Auto-detect TLS method ---
    if [ -f .docker/traefik/certs/plumber_fullchain.pem ] && [ -f .docker/traefik/certs/plumber_privkey.pem ]; then
        DETECTED_CERT="custom-certs"
        CERT_REASON="custom certificate files found in .docker/traefik/certs/"
    else
        DETECTED_CERT="letsencrypt"
        CERT_REASON="no custom certificate files found (using Let's Encrypt)"
    fi

    # --- Auto-detect database ---
    CURRENT_DB_HOST="${JOBS_DB_HOST:-postgres}"
    if [ "$CURRENT_DB_HOST" != "postgres" ]; then
        DETECTED_DB=""
        DB_REASON="JOBS_DB_HOST is set to '${CURRENT_DB_HOST}' (external database)"
    else
        DETECTED_DB=",internal-db"
        DB_REASON="JOBS_DB_HOST is 'postgres' or unset (internal database)"
    fi

    DETECTED_PROFILES="${DETECTED_CERT}${DETECTED_DB}"

    echo "  Auto-detected configuration:"
    echo -e "    TLS:      ${BOLD}${DETECTED_CERT}${NC} ${DIM}(${CERT_REASON})${NC}"
    if [ -n "$DETECTED_DB" ]; then
        echo -e "    Database: ${BOLD}internal${NC} ${DIM}(${DB_REASON})${NC}"
    else
        echo -e "    Database: ${BOLD}external${NC} ${DIM}(${DB_REASON})${NC}"
    fi
    echo ""
    echo -e "    COMPOSE_PROFILES=${BOLD}${DETECTED_PROFILES}${NC}"
    echo ""

    while true; do
        echo -ne "${BOLD}Is this correct?${NC} ${DIM}(Y/n)${NC}: "
        read -r REPLY
        REPLY="${REPLY:-Y}"
        case "$REPLY" in
            [yY][eE][sS]|[yY])
                set_env_var "COMPOSE_PROFILES" "${DETECTED_PROFILES}"
                echo -e "${GREEN}✓${NC} COMPOSE_PROFILES=${DETECTED_PROFILES} added to .env"
                break
                ;;
            [nN][oO]|[nN])
                echo ""
                echo "  Available profiles:"
                echo "    1. letsencrypt,internal-db       (Let's Encrypt + managed PostgreSQL)"
                echo "    2. custom-certs,internal-db      (Custom certs + managed PostgreSQL)"
                echo "    3. letsencrypt                   (Let's Encrypt + external PostgreSQL)"
                echo "    4. custom-certs                  (Custom certs + external PostgreSQL)"
                echo ""
                while true; do
                    echo -ne "${BOLD}Choice${NC} ${DIM}(1-4)${NC}: "
                    read -r CHOICE
                    case "$CHOICE" in
                        1) PROFILES="letsencrypt,internal-db"; break ;;
                        2) PROFILES="custom-certs,internal-db"; break ;;
                        3) PROFILES="letsencrypt"; break ;;
                        4) PROFILES="custom-certs"; break ;;
                        *) echo -e "${RED}  Please enter a number between 1 and 4.${NC}" ;;
                    esac
                done
                set_env_var "COMPOSE_PROFILES" "${PROFILES}"
                echo -e "${GREEN}✓${NC} COMPOSE_PROFILES=${PROFILES} added to .env"
                break
                ;;
            *)
                echo -e "${RED}  Please answer Y or N.${NC}"
                ;;
        esac
    done
fi

# =============================================================================
# Step 4: Restart containers
# =============================================================================
echo ""
echo "Restarting containers..."
docker compose up -d

echo ""
echo -e "${GREEN}✓ Plumber has been updated successfully!${NC}"
echo ""
