#!/bin/bash

# Plumber Installer
# Interactive setup wizard for self-managed Plumber instances.
#
# Usage:
#   # Option A: One-liner (clones the repo automatically)
#   curl -fsSL https://raw.githubusercontent.com/getplumber/platform/main/install.sh | bash
#
#   # Option B: From a cloned repository
#   git clone https://github.com/getplumber/platform.git plumber-platform
#   cd plumber-platform
#   ./install.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

REPO_URL="https://github.com/getplumber/platform.git"
REPO_DIR="plumber-platform"

# =============================================================================
# Helpers
# =============================================================================

prompt() {
    local VARNAME="$1"
    local MESSAGE="$2"
    local DEFAULT="${3:-}"
    local VALUE=""

    while true; do
        if [ -n "$DEFAULT" ]; then
            echo -ne "${BOLD}${MESSAGE}${NC} ${DIM}(${DEFAULT})${NC}: "
        else
            echo -ne "${BOLD}${MESSAGE}${NC}: "
        fi
        read -r VALUE
        VALUE="${VALUE:-$DEFAULT}"

        if [ -n "$VALUE" ]; then
            eval "$VARNAME=\"$VALUE\""
            return
        fi
        echo -e "${RED}  This field is required.${NC}"
    done
}

prompt_secret() {
    local VARNAME="$1"
    local MESSAGE="$2"
    local VALUE=""
    local CHAR=""

    while true; do
        VALUE=""
        echo -ne "${BOLD}${MESSAGE}${NC}: "
        while IFS= read -rs -n1 CHAR; do
            if [[ -z "$CHAR" ]]; then
                break
            elif [[ "$CHAR" == $'\x7f' ]] || [[ "$CHAR" == $'\b' ]]; then
                if [ -n "$VALUE" ]; then
                    VALUE="${VALUE%?}"
                    echo -ne "\b \b"
                fi
            else
                VALUE+="$CHAR"
                echo -ne "*"
            fi
        done
        echo ""

        if [ -n "$VALUE" ]; then
            eval "$VARNAME=\"$VALUE\""
            return
        fi
        echo -e "${RED}  This field is required.${NC}"
    done
}

prompt_optional() {
    local VARNAME="$1"
    local MESSAGE="$2"
    local DEFAULT="${3:-}"

    if [ -n "$DEFAULT" ]; then
        echo -ne "${BOLD}${MESSAGE}${NC} ${DIM}(${DEFAULT})${NC}: "
    else
        echo -ne "${BOLD}${MESSAGE}${NC} ${DIM}(leave empty to skip)${NC}: "
    fi
    read -r VALUE
    VALUE="${VALUE:-$DEFAULT}"
    eval "$VARNAME=\"$VALUE\""
}

prompt_choice() {
    local VARNAME="$1"
    local MESSAGE="$2"
    shift 2
    local OPTIONS=("$@")
    local NUM_OPTIONS=${#OPTIONS[@]}

    echo -e "${BOLD}${MESSAGE}${NC}"
    for i in "${!OPTIONS[@]}"; do
        echo "  $((i + 1)). ${OPTIONS[$i]}"
    done

    while true; do
        echo -ne "${BOLD}Choice${NC} ${DIM}(1-${NUM_OPTIONS})${NC}: "
        read -r CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$NUM_OPTIONS" ]; then
            eval "$VARNAME=\"$CHOICE\""
            return
        fi
        echo -e "${RED}  Please enter a number between 1 and ${NUM_OPTIONS}.${NC}"
    done
}

prompt_confirm() {
    local MESSAGE="$1"
    local DEFAULT="${2:-Y}"

    if [ "$DEFAULT" = "Y" ]; then
        echo -ne "${BOLD}${MESSAGE}${NC} ${DIM}(Y/n)${NC}: "
    else
        echo -ne "${BOLD}${MESSAGE}${NC} ${DIM}(y/N)${NC}: "
    fi
    read -r REPLY
    REPLY="${REPLY:-$DEFAULT}"

    case "$REPLY" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# =============================================================================
# Step 1: Detect context and clone if needed
# =============================================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         Plumber Installer            ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""

if [ ! -f compose.yml ] || [ ! -f versions.env ]; then
    echo "Plumber repository not detected. Cloning..."
    echo ""

    # Check git is available
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Error:${NC} Git is required but not installed."
        echo "  Install it: https://git-scm.com/downloads"
        exit 1
    fi

    # Check docker is available
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error:${NC} Docker is required but not installed."
        echo "  Install it: https://docs.docker.com/get-docker/"
        exit 1
    fi

    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
    echo ""
    echo -e "${GREEN}✓${NC} Repository cloned to $(pwd)"
    echo ""
fi

# =============================================================================
# Step 2: Run pre-config checks
# =============================================================================

echo "Running pre-flight checks..."
if ! bash scripts/preflight.sh --pre; then
    echo ""
    echo -e "${RED}Pre-flight checks failed. Please fix the issues above and try again.${NC}"
    exit 1
fi

# =============================================================================
# Step 3: Interactive configuration
# =============================================================================

echo ""
echo -e "${BOLD}Configuration${NC}"
echo "───────────────────────────────────────"
echo ""

# Domain name
prompt DOMAIN_NAME "Plumber domain name (e.g. plumber.example.com)"

# GitLab URL
prompt JOBS_GITLAB_URL "GitLab instance URL (e.g. https://gitlab.example.com)"
# Strip trailing slash
JOBS_GITLAB_URL="${JOBS_GITLAB_URL%/}"

# Organization
echo ""
echo -e "${DIM}Leave empty to connect Plumber to the entire GitLab instance.${NC}"
echo -e "${DIM}Or enter a group path to limit Plumber to that group.${NC}"
prompt_optional ORGANIZATION "GitLab group path"

# GitLab OIDC
echo ""
echo "───────────────────────────────────────"
echo -e "${BOLD}GitLab OIDC Application${NC}"
echo ""

# Ensure GitLab URL has https:// scheme for clickable terminal links
GITLAB_BASE_URL="${JOBS_GITLAB_URL}"
if [[ ! "$GITLAB_BASE_URL" =~ ^https?:// ]]; then
    GITLAB_BASE_URL="https://${GITLAB_BASE_URL}"
fi

# Build direct link to the GitLab application creation page
if [ -n "${ORGANIZATION}" ]; then
    GITLAB_APP_URL="${GITLAB_BASE_URL}/groups/${ORGANIZATION}/-/settings/applications"
else
    GITLAB_APP_URL="${GITLAB_BASE_URL}/admin/applications"
fi

echo "  1. Open this link to create a new application:"
echo ""
echo -e "     ${BOLD}${GITLAB_APP_URL}${NC}"
echo ""
echo "  2. Fill in the following:"
echo -e "     - Name:         ${BOLD}Plumber${NC}"
echo -e "     - Redirect URI: ${BOLD}https://${DOMAIN_NAME}/api/auth/gitlab/callback${NC}"
echo -e "     - Confidential: ${BOLD}yes${NC} (keep the box checked)"
echo -e "     - Scopes:       ${BOLD}api${NC}"
echo ""
echo "  3. Click Save and copy the credentials below"
echo ""

prompt GITLAB_OAUTH2_CLIENT_ID "Application ID"
prompt_secret GITLAB_OAUTH2_CLIENT_SECRET "Secret"

# Certificate method
echo ""
echo "───────────────────────────────────────"
prompt_choice CERT_CHOICE "TLS certificate method:" \
    "Let's Encrypt (automatic, server must be reachable from internet)" \
    "Custom certificates (provide your own .pem files)"

if [ "$CERT_CHOICE" = "1" ]; then
    CERT_PROFILE="letsencrypt"
else
    CERT_PROFILE="custom-certs"
    echo ""
    echo -e "${DIM}Place your certificate files at:${NC}"
    echo "  .docker/traefik/certs/plumber_fullchain.pem"
    echo "  .docker/traefik/certs/plumber_privkey.pem"

    if [ -f .docker/traefik/certs/plumber_fullchain.pem ] && [ -f .docker/traefik/certs/plumber_privkey.pem ]; then
        echo -e "  ${GREEN}✓${NC} Certificate files found"
    else
        echo -e "  ${YELLOW}!${NC} Certificate files not found yet (add them before starting)"
    fi
fi

# Database
echo ""
echo "───────────────────────────────────────"
prompt_choice DB_CHOICE "Database:" \
    "Internal (managed PostgreSQL container)" \
    "External (connect to your own PostgreSQL)"

if [ "$DB_CHOICE" = "1" ]; then
    DB_PROFILE=",internal-db"
    EXT_DB_VARS=""
else
    DB_PROFILE=""
    echo ""
    prompt JOBS_DB_HOST "Database host"
    prompt_optional JOBS_DB_PORT "Database port" "5432"
    prompt_optional JOBS_DB_USER "Database user" "jobs"
    prompt_optional JOBS_DB_NAME "Database name" "jobs"
    prompt_optional JOBS_DB_SSLMODE "SSL mode" "disable"
    prompt_optional JOBS_DB_TIMEZONE "Timezone" "Europe/Paris"

    EXT_DB_VARS=$(cat <<EXTDB

# External database configuration
JOBS_DB_HOST="${JOBS_DB_HOST}"
JOBS_DB_PORT="${JOBS_DB_PORT}"
JOBS_DB_USER="${JOBS_DB_USER}"
JOBS_DB_NAME="${JOBS_DB_NAME}"
JOBS_DB_SSLMODE="${JOBS_DB_SSLMODE}"
JOBS_DB_TIMEZONE="${JOBS_DB_TIMEZONE}"
EXTDB
)
fi

COMPOSE_PROFILES="${CERT_PROFILE}${DB_PROFILE}"

# =============================================================================
# Step 4: Generate secrets
# =============================================================================

echo ""
echo "───────────────────────────────────────"
echo "Generating secrets..."

SECRET_KEY=$(openssl rand -hex 32)
JOBS_DB_PASSWORD=$(openssl rand -hex 16)
JOBS_REDIS_PASSWORD=$(openssl rand -hex 16)

echo -e "${GREEN}✓${NC} Secrets generated"

# =============================================================================
# Step 5: Read image tags from versions.env
# =============================================================================

source versions.env

if [ -z "${FRONTEND_IMAGE_TAG:-}" ] || [ -z "${BACKEND_IMAGE_TAG:-}" ]; then
    echo -e "${RED}Error:${NC} versions.env is missing image tags."
    exit 1
fi

echo -e "${GREEN}✓${NC} Image versions: frontend=${FRONTEND_IMAGE_TAG}, backend=${BACKEND_IMAGE_TAG}"

# =============================================================================
# Step 6: Write .env
# =============================================================================

cat > .env <<ENV
##########################################################################
# Plumber configuration file                                             #
# Documentation: https://getplumber.io/docs/installation/docker-compose/ #
##########################################################################

# Main configuration
DOMAIN_NAME="${DOMAIN_NAME}"
JOBS_GITLAB_URL="${JOBS_GITLAB_URL}"
ORGANIZATION="${ORGANIZATION}"

# GitLab OIDC
GITLAB_OAUTH2_CLIENT_ID="${GITLAB_OAUTH2_CLIENT_ID}"
GITLAB_OAUTH2_CLIENT_SECRET="${GITLAB_OAUTH2_CLIENT_SECRET}"

# Secrets
SECRET_KEY="${SECRET_KEY}"
JOBS_DB_PASSWORD="${JOBS_DB_PASSWORD}"
JOBS_REDIS_PASSWORD="${JOBS_REDIS_PASSWORD}"

# Deployment profile
COMPOSE_PROFILES="${COMPOSE_PROFILES}"

# Image versions (managed by scripts/update.sh)
FRONTEND_IMAGE_TAG="${FRONTEND_IMAGE_TAG}"
BACKEND_IMAGE_TAG="${BACKEND_IMAGE_TAG}"
${EXT_DB_VARS}
ENV

echo -e "${GREEN}✓${NC} Configuration written to .env"

# =============================================================================
# Step 7: Run post-config checks
# =============================================================================

echo ""
echo "Running post-config validation..."
bash scripts/preflight.sh --post || true

# =============================================================================
# Step 8: Launch
# =============================================================================

echo ""
echo "───────────────────────────────────────"
echo ""

if prompt_confirm "Start Plumber now?"; then
    echo ""
    echo "Starting Plumber..."
    docker compose up -d
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Plumber is starting!            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Visit: ${BOLD}https://${DOMAIN_NAME}${NC}"
    echo ""
    echo "  Useful commands:"
    echo "    docker compose ps       # Check service status"
    echo "    docker compose logs -f  # View logs"
    echo "    ./scripts/update.sh     # Update to latest version"
    echo ""
else
    echo ""
    echo -e "${GREEN}Configuration complete!${NC}"
    echo ""
    echo "  To start Plumber, run:"
    echo -e "    ${BOLD}docker compose up -d${NC}"
    echo ""
    echo -e "  Then visit: ${BOLD}https://${DOMAIN_NAME}${NC}"
    echo ""
fi
