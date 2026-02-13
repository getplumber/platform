#!/bin/bash

# Plumber Pre-flight Checks
# Validates system requirements and configuration before launching Plumber.
#
# Usage:
#   ./scripts/preflight.sh              # Run all checks (pre-config + post-config)
#   ./scripts/preflight.sh --pre        # Run only pre-config checks (no .env needed)
#   ./scripts/preflight.sh --post       # Run only post-config checks (.env required)
#
# Exit codes:
#   0 = all checks passed
#   1 = fatal error (must fix before proceeding)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "  ${YELLOW}!${NC} $1"
}

# =============================================================================
# Pre-config checks (no .env needed)
# =============================================================================
run_pre_checks() {
    echo ""
    echo "Pre-config checks"
    echo "───────────────────────────────────────"

    # Check Docker is installed and running
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            pass "Docker is installed and running"
        else
            fail "Docker is installed but not running (start Docker daemon)"
        fi
    else
        fail "Docker is not installed (https://docs.docker.com/get-docker/)"
    fi

    # Check Docker Compose v2.20.2+ is available
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "0.0.0")
        MAJOR=$(echo "$COMPOSE_VERSION" | cut -d. -f1 | sed 's/v//')
        MINOR=$(echo "$COMPOSE_VERSION" | cut -d. -f2)
        PATCH=$(echo "$COMPOSE_VERSION" | cut -d. -f3)

        if [ "$MAJOR" -gt 2 ] || ([ "$MAJOR" -eq 2 ] && [ "$MINOR" -gt 20 ]) || ([ "$MAJOR" -eq 2 ] && [ "$MINOR" -eq 20 ] && [ "$PATCH" -ge 2 ]); then
            pass "Docker Compose v${COMPOSE_VERSION} (>= 2.20.2 required)"
        else
            fail "Docker Compose v${COMPOSE_VERSION} is too old (>= 2.20.2 required)"
        fi
    else
        fail "Docker Compose plugin is not installed (https://docs.docker.com/compose/install/)"
    fi

    # Check git is available
    if command -v git &> /dev/null; then
        pass "Git is installed"
    else
        fail "Git is not installed"
    fi

    # Check openssl is available (needed for secret generation)
    if command -v openssl &> /dev/null; then
        pass "OpenSSL is installed (for secret generation)"
    else
        fail "OpenSSL is not installed (needed to generate secrets)"
    fi

    # Check ports 80 and 443 are available
    for PORT in 80 443; do
        if command -v ss &> /dev/null; then
            if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
                fail "Port ${PORT} is already in use"
            else
                pass "Port ${PORT} is available"
            fi
        elif command -v lsof &> /dev/null; then
            if lsof -i ":${PORT}" -sTCP:LISTEN &> /dev/null; then
                fail "Port ${PORT} is already in use"
            else
                pass "Port ${PORT} is available"
            fi
        else
            warn "Port ${PORT}: cannot check (install lsof or ss)"
        fi
    done
}

# =============================================================================
# Post-config checks (.env required)
# =============================================================================
run_post_checks() {
    echo ""
    echo "Post-config checks"
    echo "───────────────────────────────────────"

    # Check .env exists
    if [ ! -f .env ]; then
        fail ".env file does not exist (run ./install.sh first)"
        return
    fi
    pass ".env file exists"

    # Source .env for validation
    set -a
    source .env
    set +a

    # Check required variables are set and non-empty
    REQUIRED_VARS="DOMAIN_NAME JOBS_GITLAB_URL GITLAB_OAUTH2_CLIENT_ID GITLAB_OAUTH2_CLIENT_SECRET SECRET_KEY JOBS_DB_PASSWORD JOBS_REDIS_PASSWORD COMPOSE_PROFILES"
    for VAR in $REQUIRED_VARS; do
        VALUE="${!VAR:-}"
        if [ -z "$VALUE" ]; then
            fail "$VAR is not set"
        elif echo "$VALUE" | grep -qi "REPLACE_ME"; then
            fail "$VAR still contains a placeholder value"
        else
            pass "$VAR is set"
        fi
    done

    # Check image tags are present
    for VAR in FRONTEND_IMAGE_TAG BACKEND_IMAGE_TAG; do
        VALUE="${!VAR:-}"
        if [ -z "$VALUE" ]; then
            fail "$VAR is not set (run ./install.sh or ./scripts/update.sh)"
        else
            pass "$VAR=${VALUE}"
        fi
    done

    # Check COMPOSE_PROFILES is valid
    PROFILES="${COMPOSE_PROFILES:-}"
    if [ -n "$PROFILES" ]; then
        HAS_TRAEFIK=false
        if echo "$PROFILES" | grep -q "letsencrypt"; then
            HAS_TRAEFIK=true
        fi
        if echo "$PROFILES" | grep -q "custom-certs"; then
            HAS_TRAEFIK=true
        fi
        if [ "$HAS_TRAEFIK" = false ]; then
            fail "COMPOSE_PROFILES must include 'letsencrypt' or 'custom-certs'"
        else
            pass "COMPOSE_PROFILES has a valid traefik profile"
        fi
    fi

    # Check DNS resolution for DOMAIN_NAME
    DOMAIN="${DOMAIN_NAME:-}"
    if [ -n "$DOMAIN" ]; then
        if command -v dig &> /dev/null; then
            if dig +short "$DOMAIN" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                pass "DNS resolves for ${DOMAIN}"
            else
                warn "DNS does not resolve for ${DOMAIN} (ensure your DNS record is configured)"
            fi
        elif command -v nslookup &> /dev/null; then
            if nslookup "$DOMAIN" &> /dev/null; then
                pass "DNS resolves for ${DOMAIN}"
            else
                warn "DNS does not resolve for ${DOMAIN} (ensure your DNS record is configured)"
            fi
        else
            warn "Cannot check DNS (install dig or nslookup)"
        fi
    fi

    # Check GitLab URL is reachable
    GITLAB_URL="${JOBS_GITLAB_URL:-}"
    if [ -n "$GITLAB_URL" ]; then
        if curl -sf --max-time 10 "${GITLAB_URL}" -o /dev/null 2>/dev/null; then
            pass "GitLab instance is reachable at ${GITLAB_URL}"
        else
            warn "Cannot reach GitLab at ${GITLAB_URL} (check URL and network)"
        fi
    fi

    # Check custom cert files exist if custom-certs profile is active
    if echo "${COMPOSE_PROFILES:-}" | grep -q "custom-certs"; then
        if [ -f .docker/traefik/certs/plumber_fullchain.pem ] && [ -f .docker/traefik/certs/plumber_privkey.pem ]; then
            pass "Custom certificate files found"
        else
            fail "Custom certificates profile is active but cert files are missing"
            echo -e "      Expected: .docker/traefik/certs/plumber_fullchain.pem"
            echo -e "      Expected: .docker/traefik/certs/plumber_privkey.pem"
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

# Determine which checks to run based on arguments
MODE="${1:-all}"

case "$MODE" in
    --pre)
        run_pre_checks
        ;;
    --post)
        run_post_checks
        ;;
    *)
        run_pre_checks
        run_post_checks
        ;;
esac

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo -e "${RED}$ERRORS check(s) failed.${NC} Please fix the issues above before proceeding."
    exit 1
else
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
fi
