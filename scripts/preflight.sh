#!/bin/bash

# Plumber Pre-flight Checks
# Validates system requirements and configuration before launching Plumber.
#
# Usage:
#   ./scripts/preflight.sh              # Run all checks (pre-config + post-config)
#   ./scripts/preflight.sh --pre        # Run only pre-config checks (no .env needed)
#   ./scripts/preflight.sh --post       # Run only post-config checks (.env required)
#   ./scripts/preflight.sh --pre --local  # Pre-config for local dev (port 3000)
#   ./scripts/preflight.sh --post --local # Post-config for local dev (skip domain/TLS)
#
# Exit codes:
#   0 = all checks passed
#   1 = fatal error (must fix before proceeding)
#
# Set PLUMBER_PREFLIGHT_OFFLINE=1 to skip the DNS and GitLab reachability checks (CI).

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
LOCAL_MODE=false

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

    # Check required ports are available
    if [ "$LOCAL_MODE" = true ]; then
        CHECK_PORTS="3000"
    else
        CHECK_PORTS="80 443"
    fi
    for PORT in $CHECK_PORTS; do
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
    # shellcheck disable=SC1091
    source .env
    set +a

    # Check required variables are set and non-empty
    if [ "$LOCAL_MODE" = true ]; then
        REQUIRED_VARS="GITLAB_URL PLUMBER_TOKEN_ENCRYPTION_KEY PLUMBER_DB_PASSWORD PLUMBER_REDIS_PASSWORD"
    else
        REQUIRED_VARS="DOMAIN_NAME GITLAB_URL PLUMBER_TOKEN_ENCRYPTION_KEY PLUMBER_DB_PASSWORD PLUMBER_REDIS_PASSWORD COMPOSE_PROFILES"
    fi
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

    # The encryption key seals every stored secret: exactly 32 bytes as hex.
    KEY="${PLUMBER_TOKEN_ENCRYPTION_KEY:-}"
    if [ -n "$KEY" ]; then
        if [[ "$KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
            pass "PLUMBER_TOKEN_ENCRYPTION_KEY is 64 hex characters"
        else
            fail "PLUMBER_TOKEN_ENCRYPTION_KEY must be exactly 64 hex characters (openssl rand -hex 32)"
        fi
    fi

    # Check the image pin is present
    if [ -z "${PLATFORM_VERSION:-}" ]; then
        fail "PLATFORM_VERSION is not set (run ./install.sh or ./scripts/update.sh)"
    else
        pass "PLATFORM_VERSION=${PLATFORM_VERSION}"
    fi

    # Custom CA bundle consistency (any deployment type, any TLS method)
    CA_DIR=".docker/ca-certificates"
    CA_COUNT=$(find "$CA_DIR" -maxdepth 1 -type f \( -name "*.pem" -o -name "*.crt" \) ! -name "plumber-ca.bundle" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$CA_COUNT" -gt 0 ]; then
        if [ -f "$CA_DIR/plumber-ca.bundle" ] && [ -n "${PLUMBER_PROVIDER_CA_BUNDLE:-}" ]; then
            pass "Found ${CA_COUNT} custom CA certificate(s), bundle built and PLUMBER_PROVIDER_CA_BUNDLE set"
        else
            fail "Custom CA certificates found but the bundle is missing (run ./scripts/ca-bundle.sh)"
        fi
        for CA_FILE in "$CA_DIR"/*.pem "$CA_DIR"/*.crt; do
            [ -f "$CA_FILE" ] || continue
            if openssl x509 -in "$CA_FILE" -noout 2>/dev/null; then
                pass "CA certificate $(basename "$CA_FILE") is a valid PEM"
            else
                fail "CA certificate $(basename "$CA_FILE") is not a valid PEM file"
            fi
        done
    elif [ -n "${PLUMBER_PROVIDER_CA_BUNDLE:-}" ]; then
        fail "PLUMBER_PROVIDER_CA_BUNDLE is set but ${CA_DIR}/ has no certificates (run ./scripts/ca-bundle.sh)"
    else
        pass "No custom CA (not needed for publicly-signed GitLab certificates)"
    fi

    # Production-only checks
    if [ "$LOCAL_MODE" = false ]; then
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
        if [ -n "$DOMAIN" ] && [ -z "${PLUMBER_PREFLIGHT_OFFLINE:-}" ]; then
            if command -v dig &> /dev/null; then
                if dig +short "$DOMAIN" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                    pass "DNS resolves for ${DOMAIN}"
                else
                    fail "DNS does not resolve for ${DOMAIN} (ensure your DNS record is configured)"
                fi
            elif command -v nslookup &> /dev/null; then
                if nslookup "$DOMAIN" &> /dev/null; then
                    pass "DNS resolves for ${DOMAIN}"
                else
                    fail "DNS does not resolve for ${DOMAIN} (ensure your DNS record is configured)"
                fi
            else
                warn "Cannot check DNS (install dig or nslookup)"
            fi
        fi

        # Check custom cert files if custom-certs profile is active
        if echo "${COMPOSE_PROFILES:-}" | grep -q "custom-certs"; then
            CERT_DIR=".docker/traefik/certs"
            FULLCHAIN="${CERT_DIR}/plumber_fullchain.pem"
            PRIVKEY="${CERT_DIR}/plumber_privkey.pem"

            if [ -f "$FULLCHAIN" ] && [ -f "$PRIVKEY" ]; then
                pass "Custom certificate files found"

                # Validate certificate is a valid PEM
                if openssl x509 -in "$FULLCHAIN" -noout 2>/dev/null; then
                    pass "Certificate ${FULLCHAIN} is a valid PEM"
                else
                    fail "Certificate ${FULLCHAIN} is not a valid PEM file"
                fi

                # Validate private key is a valid PEM
                if openssl rsa -in "$PRIVKEY" -check -noout >/dev/null 2>&1 || openssl ec -in "$PRIVKEY" -check -noout >/dev/null 2>&1; then
                    pass "Private key ${PRIVKEY} is valid"
                else
                    fail "Private key ${PRIVKEY} is not a valid PEM key file"
                fi
            else
                fail "Custom certificates profile is active but cert files are missing"
                echo -e "      Expected: ${FULLCHAIN}"
                echo -e "      Expected: ${PRIVKEY}"
            fi
        fi
    fi

    # Check GitLab URL is reachable
    GITLAB_TARGET="${GITLAB_URL:-}"
    if [ -n "$GITLAB_TARGET" ] && [ -z "${PLUMBER_PREFLIGHT_OFFLINE:-}" ]; then
        if curl -sf --max-time 10 "${GITLAB_TARGET}" -o /dev/null 2>/dev/null; then
            pass "GitLab instance is reachable at ${GITLAB_TARGET}"
        else
            fail "Cannot reach GitLab at ${GITLAB_TARGET} (check URL and network)"
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

# Parse arguments
MODE="all"
for ARG in "$@"; do
    case "$ARG" in
        --pre) MODE="pre" ;;
        --post) MODE="post" ;;
        --local) LOCAL_MODE=true ;;
    esac
done

case "$MODE" in
    pre)
        run_pre_checks
        ;;
    post)
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
