# Plumber Platform (self-managed)

[![CI](https://github.com/getplumber/platform/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/getplumber/platform/actions/workflows/ci.yml)

Everything needed to self-host the [Plumber](https://getplumber.io/) Platform, the CI/CD security
and compliance control plane. Analysis stays in the open-source
[CLI](https://github.com/getplumber/plumber), which pushes results here over native CI OIDC.

This is the **v2** line: images `docker.io/getplumber/platform-backend` and
`docker.io/getplumber/platform-frontend`, one version for both (`versions.env`), Helm chart
`plumber-platform`. The previous line (v1: chart `plumber`, its own images and installer) lives
unchanged in [`legacy-v1/`](legacy-v1/); the two are not compatible and do not share a database.

## Docker Compose

Requirements: a Linux host with Docker (Compose plugin 2.20+), git, openssl, ports 80 and 443
free, a DNS record for your domain, and a GitLab instance (17.7+ recommended).

### Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/getplumber/platform/main/install.sh | bash
```

Choose **Production**. The installer checks prerequisites, asks for the domain, the GitLab URL,
the connection scope (whole instance or one root group), the GitLab OAuth application (it prints
the exact redirect URI, `https://<domain>/api/v1/auth/callback`, and the link to create it), an
optional access token, the TLS method (Let's Encrypt or your own certificates), an optional
private CA and the database (bundled or external). It generates the secrets, writes `.env`, starts
the stack and configures the GitLab connection. Then open `https://<domain>` and sign in with
GitLab: the first account becomes the organisation Admin.

Choose **Local** for a laptop install on `http://localhost:3000` (no TLS).

### Manual install

```bash
git clone https://github.com/getplumber/platform.git plumber-platform
cd plumber-platform
cp .env.example .env
cat versions.env >> .env
```

Fill `.env`: `DOMAIN_NAME`, `GITLAB_URL`, `PLUMBER_TOKEN_ENCRYPTION_KEY` (`openssl rand -hex 32`,
back it up: it seals every stored secret and cannot be rotated in place), `PLUMBER_DB_PASSWORD`
and `PLUMBER_REDIS_PASSWORD` (`openssl rand -hex 16`), then pick a profile:

| `COMPOSE_PROFILES` | `CERT_RESOLVER` | Meaning |
|---|---|---|
| `letsencrypt,internal-db` | `le` | Let's Encrypt + bundled Postgres |
| `custom-certs,internal-db` | (empty) | Your certificates in `.docker/traefik/certs/plumber_fullchain.pem` and `plumber_privkey.pem` + bundled Postgres |
| `letsencrypt` or `custom-certs` | as above | External Postgres: set `PLUMBER_DB_HOST` and friends in `.env` |

Private CA for GitLab: drop the `.pem`/`.crt` files in `.docker/ca-certificates/` and run
`./scripts/ca-bundle.sh` (both containers trust them).

```bash
./scripts/preflight.sh
docker compose up -d
```

Then configure the GitLab connection once (create an OAuth application first: redirect URI
`https://<domain>/api/v1/auth/callback`, confidential, scope `api`):

```bash
read -rs -p "OAuth application secret: " PLUMBER_BOOTSTRAP_CLIENT_SECRET; echo; export PLUMBER_BOOTSTRAP_CLIENT_SECRET
docker compose exec -T -e PLUMBER_BOOTSTRAP_CLIENT_SECRET \
  backend plumber-bootstrap -base-url https://gitlab.example.com -client-id <application-id> -scope instance
```

Use `-scope group -root-group <path>` to scope to one root group, and export
`PLUMBER_BOOTSTRAP_TOKEN` the same way (add `-e PLUMBER_BOOTSTRAP_TOKEN`) to store an access token
(`api` scope) in the same run.
The command refuses an already-configured instance, so it is safe to retry on a fresh install.

### Update, backup, restore

```bash
./scripts/update.sh            # pulls the repo, syncs PLATFORM_VERSION from versions.env, restarts
./scripts/backup.sh 18         # database dump + .env (+ CA files) into backups/, optional S3 upload
./scripts/restore.sh 18 <file> # the reverse
```

Every release pins both images to one version. Upgrades are sequential and additive (the backend
migrates the database on boot); rolling back is reverting `PLATFORM_VERSION` in `.env` and
`docker compose up -d`. Never downgrade the database by hand.

## Kubernetes (Helm)

```bash
helm repo add plumber https://charts.getplumber.io/
helm repo update
helm upgrade --install plumber plumber/plumber-platform -n plumber --create-namespace -f values.yaml
```

See [`charts/plumber-platform/README.md`](charts/plumber-platform/README.md) for the minimal
values (one ingress host serves both apps), the secrets, the bundled or external Postgres and
Redis, the private CA options and the first-run bootstrap (manual command or the post-install Job).

## Releases

Each release is a git tag `vX.Y.Z` with a GitHub Release carrying the changelog and the packaged
chart; `latest.json` is what installs poll for the update banner. `releases/` holds the notes.

## Legacy v1

The previous install line (Helm chart `plumber`, Compose with bundled Traefik, podman,
`install.sh`) lives unchanged in [`legacy-v1/`](legacy-v1/). See `legacy-v1/README.md`.

## Contributions

You are welcome to help us improve this repository! Open an Issue or create a Pull Request from
your fork.
