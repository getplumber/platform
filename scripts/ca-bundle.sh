#!/bin/bash

# Plumber CA bundle builder
# Concatenates every .pem/.crt in .docker/ca-certificates/ into one bundle the
# backend can read (PLUMBER_PROVIDER_CA_BUNDLE takes a single PEM path) and
# keeps the matching line in .env in sync. The frontend needs no bundle: its
# image entrypoint reads the same directory file by file.
#
# Usage: ./scripts/ca-bundle.sh      (run from the repository root)
# Called automatically by install.sh and scripts/update.sh.

set -euo pipefail

CA_DIR=".docker/ca-certificates"
BUNDLE_NAME="plumber-ca.bundle"
BUNDLE="$CA_DIR/$BUNDLE_NAME"
ENV_KEY="PLUMBER_PROVIDER_CA_BUNDLE"
ENV_VALUE="/usr/local/share/ca-certificates/$BUNDLE_NAME"

if [ ! -f .env ]; then
    echo "Error: .env not found (run ./install.sh first)." >&2
    exit 1
fi
mkdir -p "$CA_DIR"

CERTS=()
for f in "$CA_DIR"/*.pem "$CA_DIR"/*.crt; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "$BUNDLE_NAME" ] && continue
    if ! openssl x509 -in "$f" -noout 2>/dev/null; then
        echo "Error: $f is not a valid PEM certificate." >&2
        exit 1
    fi
    CERTS+=("$f")
done

remove_env_line() {
    sed -i."" "/^${ENV_KEY}=/d" .env
    rm -f .env."" 2>/dev/null || true
}

if [ "${#CERTS[@]}" -eq 0 ]; then
    rm -f "$BUNDLE"
    remove_env_line
    echo "No custom CA certificates in $CA_DIR/ (nothing to do)."
    exit 0
fi

TMP="$BUNDLE.tmp"
: > "$TMP"
for f in "${CERTS[@]}"; do
    cat "$f" >> "$TMP"
    printf '\n' >> "$TMP"
done
mv "$TMP" "$BUNDLE"
chmod 644 "$BUNDLE"

remove_env_line
printf "%s='%s'\n" "$ENV_KEY" "$ENV_VALUE" >> .env
echo "Built $BUNDLE from ${#CERTS[@]} certificate(s); $ENV_KEY set in .env."
echo "Restart the apps so they pick it up: docker compose up -d --force-recreate backend frontend (or the compose.local.yml equivalent)."
