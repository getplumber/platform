#!/usr/bin/env bash
# Renders compose.yml (every supported profile combination) and compose.local.yml
# against a throwaway .env, then asserts the v2 wiring facts that a reviewer
# would otherwise have to eyeball: image pins, one-origin routing, env names,
# volumes, no in-container healthchecks on the two apps. Runs in CI and locally:
#   scripts/ci/compose-check.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ENV="$TMP/.env"
cat .env.example versions.env > "$ENV"
KEY=$(printf '0%.0s' $(seq 64))
sed -i \
  -e 's|^DOMAIN_NAME=.*|DOMAIN_NAME="plumber.example.com"|' \
  -e 's|^GITLAB_URL=.*|GITLAB_URL="https://gitlab.example.com"|' \
  -e "s|^PLUMBER_TOKEN_ENCRYPTION_KEY=.*|PLUMBER_TOKEN_ENCRYPTION_KEY=\"$KEY\"|" \
  -e 's|^PLUMBER_DB_PASSWORD=.*|PLUMBER_DB_PASSWORD="dbpass"|' \
  -e 's|^PLUMBER_REDIS_PASSWORD=.*|PLUMBER_REDIS_PASSWORD="redispass"|' "$ENV"
VERSION=$(sed -n 's/^PLATFORM_VERSION=//p' versions.env)

FAILED=0
check() { # check <label> <jq boolean filter> <json>
  if jq -e "$2" >/dev/null <<<"$3"; then echo "  ok   $1"; else echo "  FAIL $1"; FAILED=1; fi
}
render() { # render <file> <profiles>
  COMPOSE_PROFILES="$2" docker compose --env-file "$ENV" -f "$1" config --format json
}

for profiles in "letsencrypt,internal-db" "custom-certs,internal-db" "letsencrypt" "custom-certs"; do
  echo "compose.yml [$profiles]"
  J=$(render compose.yml "$profiles")
  check "backend image pinned by versions.env" ".services.backend.image == \"docker.io/getplumber/platform-backend:$VERSION\"" "$J"
  check "frontend image pinned by versions.env" ".services.frontend.image == \"docker.io/getplumber/platform-frontend:$VERSION\"" "$J"
  check "backend base url is https://DOMAIN_NAME" '.services.backend.environment.PLUMBER_BASE_URL == "https://plumber.example.com"' "$J"
  check "oidc audience equals base url" '.services.backend.environment.PLUMBER_OIDC_AUDIENCE == "https://plumber.example.com"' "$J"
  check "allowed issuers default to GITLAB_URL" '.services.backend.environment.PLUMBER_OIDC_ALLOWED_ISSUERS == "https://gitlab.example.com"' "$J"
  check "redis url carries the password" '.services.backend.environment.PLUMBER_REDIS_URL == "redis://default:redispass@redis:6379/0"' "$J"
  check "redis addr is never set alongside the url" '.services.backend.environment | has("PLUMBER_REDIS_ADDR") | not' "$J"
  check "cookie secure and forwarded-for trust on behind traefik" '.services.backend.environment.PLUMBER_COOKIE_SECURE == "true" and .services.backend.environment.PLUMBER_TRUST_FORWARDED_FOR == "true"' "$J"
  check "backend has no in-container healthcheck (distroless)" '.services.backend | has("healthcheck") | not' "$J"
  check "frontend has no in-container healthcheck" '.services.frontend | has("healthcheck") | not' "$J"
  check "frontend server-side api url" '.services.frontend.environment.API_INTERNAL_URL == "http://backend:8080/api"' "$J"
  check "frontend gitlab url" '.services.frontend.environment.GITLAB_URL == "https://gitlab.example.com"' "$J"
  check "both apps mount the ca-certificates dir" '[.services.backend, .services.frontend] | all(.volumes | any(.target == "/usr/local/share/ca-certificates"))' "$J"
  check "api router routes /api to port 8080" '.services.backend.labels["traefik.http.routers.api.rule"] == "Host(`plumber.example.com`)&&PathPrefix(`/api`)" and .services.backend.labels["traefik.http.services.api.loadbalancer.server.port"] == "8080"' "$J"
  check "front router routes the host to port 3000" '.services.frontend.labels["traefik.http.routers.front.rule"] == "Host(`plumber.example.com`)" and .services.frontend.labels["traefik.http.services.front.loadbalancer.server.port"] == "3000"' "$J"
  check "apps publish no host ports (traefik is the only entry)" '[.services.backend, .services.frontend, .services.redis, (.services.postgres // {})] | all(has("ports") | not)' "$J"
  check "redis requires the password" '.services.redis.command | index("--requirepass redispass")' "$J"
  case "$profiles" in
    *internal-db*)
      check "postgres present" '.services | has("postgres")' "$J"
      check "postgres 18 mounts /var/lib/postgresql (not .../data)" '.services.postgres.volumes | any(.target == "/var/lib/postgresql")' "$J"
      check "postgres PGDATA set" '.services.postgres.environment.PGDATA == "/var/lib/postgresql/18/data"' "$J" ;;
    *) check "postgres absent without internal-db" '.services | has("postgres") | not' "$J" ;;
  esac
  case "$profiles" in
    letsencrypt*)
      check "traefik-le present" '.services | has("traefik-le")' "$J"
      check "traefik-custom-certs absent" '.services | has("traefik-custom-certs") | not' "$J"
      check "letsencrypt resolver on both routers" '.services.frontend.labels["traefik.http.routers.front.tls.certresolver"] == "le" and .services.backend.labels["traefik.http.routers.api.tls.certresolver"] == "le"' "$J" ;;
    custom-certs*)
      check "traefik-custom-certs present" '.services | has("traefik-custom-certs")' "$J"
      check "traefik-le absent" '.services | has("traefik-le") | not' "$J"
      check "custom certs file provider mounted" '.services["traefik-custom-certs"].volumes | any(.target == "/etc/traefik/certs.yml")' "$J" ;;
  esac
  check "traefik publishes 80 and 443 only" '[.services[] | select(.ports) | .ports[] | .published] | sort == ["443","80"]' "$J"
done

if [ -f compose.local.yml ]; then
  echo "compose.local.yml"
  J=$(render compose.local.yml "")
  check "local traefik publishes 3000 -> 80" '.services.traefik.ports | any(.published == "3000" and .target == 80)' "$J"
  check "local base url is http://localhost:3000" '.services.backend.environment.PLUMBER_BASE_URL == "http://localhost:3000"' "$J"
  check "local cookies are not Secure (plain http)" '.services.backend.environment.PLUMBER_COOKIE_SECURE == "false"' "$J"
  check "local apps publish no host ports" '[.services.backend, .services.frontend, .services.redis, .services.postgres] | all(has("ports") | not)' "$J"
  check "local api router is /api on 8080" '.services.backend.labels["traefik.http.routers.api.rule"] == "PathPrefix(`/api`)" and .services.backend.labels["traefik.http.services.api.loadbalancer.server.port"] == "8080"' "$J"
  check "local postgres mounts /var/lib/postgresql" '.services.postgres.volumes | any(.target == "/var/lib/postgresql")' "$J"
  check "local redis url carries the password" '.services.backend.environment.PLUMBER_REDIS_URL == "redis://default:redispass@redis:6379/0"' "$J"
fi

[ "$FAILED" = 0 ] && echo "compose-check: all good" || { echo "compose-check: FAILED"; exit 1; }
