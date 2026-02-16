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
        stty -echo 2>/dev/null || true
        while IFS= read -r -n1 CHAR; do
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
        stty echo 2>/dev/null || true
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
# Step 2: Choose deployment type
# =============================================================================

prompt_choice DEPLOY_TYPE "Deployment type:" \
    "Production (domain, TLS, reverse proxy)" \
    "Local (localhost, no TLS)"
echo ""

# =============================================================================
# Step 3: Run pre-config checks
# =============================================================================

echo "Running pre-flight checks..."
if [ "$DEPLOY_TYPE" = "2" ]; then
    PREFLIGHT_FLAGS="--pre --local"
else
    PREFLIGHT_FLAGS="--pre"
fi
if ! bash scripts/preflight.sh $PREFLIGHT_FLAGS; then
    echo ""
    echo -e "${RED}Pre-flight checks failed. Please fix the issues above and try again.${NC}"
    exit 1
fi

# =============================================================================
# Step 4: Interactive configuration
# =============================================================================

echo ""
echo -e "${BOLD}Configuration${NC}"
echo "───────────────────────────────────────"
echo ""

# Domain name (production only)
if [ "$DEPLOY_TYPE" = "1" ]; then
    prompt DOMAIN_NAME "Plumber domain name (e.g. plumber.example.com)"

    # Check DNS resolution
    DNS_OK=false
    if command -v dig &> /dev/null; then
        if dig +short "$DOMAIN_NAME" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            DNS_OK=true
        fi
    elif command -v nslookup &> /dev/null; then
        if nslookup "$DOMAIN_NAME" &> /dev/null; then
            DNS_OK=true
        fi
    fi

    if [ "$DNS_OK" = true ]; then
        echo -e "${GREEN}✓${NC} DNS resolves for ${DOMAIN_NAME}"
    else
        echo -e "${RED}!${NC} DNS does not resolve for ${DOMAIN_NAME}"
        echo -e "${DIM}  Create a DNS A record pointing ${DOMAIN_NAME} to your server's public IP.${NC}"
        echo -e "${DIM}  You can continue the setup and configure DNS before starting Plumber.${NC}"
    fi
    echo ""
fi

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
if [ "$DEPLOY_TYPE" = "1" ]; then
    REDIRECT_URI="https://${DOMAIN_NAME}/api/auth/gitlab/callback"
else
    REDIRECT_URI="http://localhost:3001/api/auth/gitlab/callback"
fi

echo "  2. Fill in the following:"
echo -e "     - Name:         ${BOLD}Plumber${NC}"
echo -e "     - Redirect URI: ${BOLD}${REDIRECT_URI}${NC}"
echo -e "     - Confidential: ${BOLD}yes${NC} (keep the box checked)"
echo -e "     - Scopes:       ${BOLD}api${NC}"
echo ""
echo "  3. Click Save and copy the credentials below"
echo ""

prompt GITLAB_OAUTH2_CLIENT_ID "Application ID"
prompt_secret GITLAB_OAUTH2_CLIENT_SECRET "Secret"

# Certificate method & Database (production only)
EXT_DB_VARS=""

if [ "$DEPLOY_TYPE" = "1" ]; then
    echo ""
    echo "───────────────────────────────────────"
    prompt_choice CERT_CHOICE "TLS certificate method:" \
        "Let's Encrypt (automatic, server must be reachable from internet)" \
        "Custom certificates (provide your own .pem files)"

    if [ "$CERT_CHOICE" = "1" ]; then
        CERT_PROFILE="letsencrypt"
        CERT_RESOLVER="le"
    else
        CERT_PROFILE="custom-certs"
        CERT_RESOLVER=""
        echo ""
        echo -e "${DIM}Place your certificate files at:${NC}"
        echo "  .docker/traefik/certs/plumber_fullchain.pem"
        echo "  .docker/traefik/certs/plumber_privkey.pem"

        if [ -f .docker/traefik/certs/plumber_fullchain.pem ] && [ -f .docker/traefik/certs/plumber_privkey.pem ]; then
            echo -e "  ${GREEN}✓${NC} Certificate files found"
        else
            echo -e "  ${YELLOW}!${NC} Certificate files not found yet (add them before starting)"
        fi

        # Custom CA
        echo ""
        echo -e "${BOLD}Custom Certificate Authority${NC}"
        echo ""
        echo -e "${DIM}If your GitLab instance or your Plumber certificates are signed by${NC}"
        echo -e "${DIM}a custom Certificate Authority (private CA), Plumber needs the root${NC}"
        echo -e "${DIM}CA certificate to trust those connections.${NC}"
        echo ""

        if prompt_confirm "Are you using a custom CA?" "N"; then
            echo ""
            echo "  Add your root CA certificate file (.pem or .crt) to:"
            echo ""
            echo -e "     ${BOLD}.docker/ca-certificates/${NC}"
            echo ""

            mkdir -p .docker/ca-certificates

            CA_FILES=$(find .docker/ca-certificates -maxdepth 1 -type f \( -name "*.pem" -o -name "*.crt" \) 2>/dev/null | wc -l | tr -d ' ')
            if [ "$CA_FILES" -gt 0 ]; then
                echo -e "  ${GREEN}✓${NC} Found ${CA_FILES} CA certificate(s) in .docker/ca-certificates/"
            else
                echo -e "  ${YELLOW}!${NC} No CA certificates found yet (add them before starting)"
            fi
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
    else
        DB_PROFILE=""
        echo ""
        prompt JOBS_DB_HOST "Database host"
        prompt_optional JOBS_DB_PORT "Database port" "5432"
        prompt JOBS_DB_USER "Database user"
        prompt_optional JOBS_DB_NAME "Database name" "plumber"
        prompt_secret JOBS_DB_PASSWORD_EXT "Database password"
        echo ""
        echo -e "${DIM}SSL mode options: disable, require, verify-ca${NC}"
        prompt_optional JOBS_DB_SSLMODE "SSL mode" "disable"

        # Detect server timezone
        SERVER_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
        prompt_optional JOBS_DB_TIMEZONE "Timezone" "${SERVER_TZ}"

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
fi

# =============================================================================
# Step 5: Generate secrets
# =============================================================================

echo ""
echo "───────────────────────────────────────"
echo "Generating secrets..."

SECRET_KEY=$(openssl rand -hex 32)
if [ -z "${JOBS_DB_PASSWORD_EXT:-}" ]; then
    JOBS_DB_PASSWORD=$(openssl rand -hex 16)
else
    JOBS_DB_PASSWORD="${JOBS_DB_PASSWORD_EXT}"
fi
JOBS_REDIS_PASSWORD=$(openssl rand -hex 16)

echo -e "${GREEN}✓${NC} Secrets generated"

# =============================================================================
# Step 6: Read image tags from versions.env
# =============================================================================

source versions.env

if [ -z "${FRONTEND_IMAGE_TAG:-}" ] || [ -z "${BACKEND_IMAGE_TAG:-}" ]; then
    echo -e "${RED}Error:${NC} versions.env is missing image tags."
    exit 1
fi

echo -e "${GREEN}✓${NC} Image versions: frontend=${FRONTEND_IMAGE_TAG}, backend=${BACKEND_IMAGE_TAG}"

# =============================================================================
# Step 7: Write .env
# =============================================================================

if [ "$DEPLOY_TYPE" = "2" ]; then
    # Local development .env (simpler, no domain/profiles/cert-resolver)
    cat > .env <<ENV
###############################################################################
# Plumber local configuration file                                            #
# Documentation: https://getplumber.io/docs/installation/local-docker-compose #
###############################################################################

# Main
JOBS_GITLAB_URL="${JOBS_GITLAB_URL}"
ORGANIZATION="${ORGANIZATION}"

# GitLab OIDC
GITLAB_OAUTH2_CLIENT_ID="${GITLAB_OAUTH2_CLIENT_ID}"
GITLAB_OAUTH2_CLIENT_SECRET="${GITLAB_OAUTH2_CLIENT_SECRET}"

# Secrets
SECRET_KEY="${SECRET_KEY}"
JOBS_DB_PASSWORD="${JOBS_DB_PASSWORD}"
JOBS_REDIS_PASSWORD="${JOBS_REDIS_PASSWORD}"

# Image versions (managed by scripts/update.sh)
FRONTEND_IMAGE_TAG="${FRONTEND_IMAGE_TAG}"
BACKEND_IMAGE_TAG="${BACKEND_IMAGE_TAG}"
ENV
else
    # Production .env
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
CERT_RESOLVER="${CERT_RESOLVER}"

# Image versions (managed by scripts/update.sh)
FRONTEND_IMAGE_TAG="${FRONTEND_IMAGE_TAG}"
BACKEND_IMAGE_TAG="${BACKEND_IMAGE_TAG}"
${EXT_DB_VARS}
ENV
fi

echo -e "${GREEN}✓${NC} Configuration written to .env"

# =============================================================================
# Step 8: Run post-config checks
# =============================================================================

echo ""
echo "Running post-config validation..."
if [ "$DEPLOY_TYPE" = "2" ]; then
    bash scripts/preflight.sh --post --local || true
else
    bash scripts/preflight.sh --post || true
fi

# =============================================================================
# Step 9: Launch
# =============================================================================

echo ""
echo "───────────────────────────────────────"
echo ""

if [ "$DEPLOY_TYPE" = "2" ]; then
    COMPOSE_CMD="docker compose -f compose.local.yml"
    PLUMBER_URL="http://localhost:3000"
else
    COMPOSE_CMD="docker compose"
    PLUMBER_URL="https://${DOMAIN_NAME}"
fi

if prompt_confirm "Start Plumber now?"; then
    echo ""
    echo "Starting Plumber..."
    $COMPOSE_CMD up -d
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Plumber is starting!            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Visit: ${BOLD}${PLUMBER_URL}${NC}"
    echo ""
    echo "  Useful commands:"
    echo "    ${COMPOSE_CMD} ps       # Check service status"
    echo "    ${COMPOSE_CMD} logs -f  # View logs"
    echo "    ./scripts/update.sh     # Update to latest version"
    echo ""
else
    echo ""
    echo -e "${GREEN}Configuration complete!${NC}"
    echo ""
    echo "  To start Plumber, run:"
    echo -e "    ${BOLD}${COMPOSE_CMD} up -d${NC}"
    echo ""
    echo -e "  Then visit: ${BOLD}${PLUMBER_URL}${NC}"
    echo ""
fi
