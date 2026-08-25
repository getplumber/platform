# Plumber Platform (self-managed)

[![CI](https://github.com/getplumber/platform/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/getplumber/platform/actions/workflows/ci.yml)

This repository contains everything needed to self-host [Plumber](https://getplumber.io/), the
CI/CD security & compliance control plane: [analysis stays in the open-source
CLI](https://github.com/getplumber/plumber), pushed here over native CI OIDC. This is the **v2**
line (compose-first, images published as `docker.io/getplumber/platform-backend` and
`docker.io/getplumber/platform-frontend`). Looking for the previous Helm/Compose/podman line? It
still lives, unchanged, in [`legacy-v1/`](legacy-v1/) - see `legacy-v1/README.md`.

## Quick start (Docker Compose)

Requires Docker with the Compose plugin (`docker compose version`).

1. **Configure.**

   ```bash
   cp .env.example .env
   ```

   Fill in every variable under "Required" in `.env` - the public URL, the GitLab instance(s)
   allowed to push analysis results, and two secrets (`.env.example` gives you the exact
   `openssl` command for each one). Leave the rest at their defaults for a first install; every
   optional hardening knob is documented, commented out, in `.env.example` and `compose.yml`.

2. **Start the stack.**

   ```bash
   docker compose up -d
   ```

   This starts Postgres, Redis, the backend (runs its own database migrations on boot), and the
   frontend. Give it a minute the first time - `docker compose ps` should show the backend and
   frontend as `healthy` once migrations have applied and both apps are answering.

3. **Bootstrap the first GitLab instance.**

   A fresh install has no configured GitLab connection yet, so there is nothing to log in
   against. Run the bootstrap command once, inside the backend container, to configure it:

   ```bash
   docker compose exec -e PLUMBER_BOOTSTRAP_CLIENT_SECRET=<your-gitlab-oauth-app-secret> \
     backend plumber-bootstrap \
     -base-url https://gitlab.example.com \
     -client-id <your-gitlab-oauth-app-client-id> \
     -scope instance
   ```

   - `-base-url` and `-client-id` are required; create a GitLab OAuth application first (redirect
     URI `<PLUMBER_BASE_URL>/auth/callback`) and pass its client id/secret here.
   - `-e PLUMBER_BOOTSTRAP_CLIENT_SECRET=...` keeps the secret out of the container's own process
     list (`-client-secret <value>` also works but is both shell-history- and `ps`-visible inside
     the container - prefer the env form). The same applies to `-token`/
     `PLUMBER_BOOTSTRAP_TOKEN` below.
   - `-scope instance` connects every project on that GitLab instance; use `-scope group
     -root-group <path>` instead to scope to one root group. Omit `-scope` entirely to leave the
     connection scope unset for now (configure it later through the settings UI as an Admin).
   - Optionally add `-e PLUMBER_BOOTSTRAP_TOKEN=<org-token>` to validate and store an org token in
     the same run (sealed before storage, never printed) - with `-scope group` this also resolves
     the root group immediately. Without a token, the connection is stored but cannot sync until
     an Admin adds one later through the settings UI.
   - The command prints a login hint on success (it never prints a secret or token). It is
     self-limiting: it refuses to touch an already-configured instance, so it is always safe to
     re-run against a fresh install and impossible to run twice by accident against a live one.

4. **Log in.** Visit `PLUMBER_BASE_URL` (via your reverse proxy - see the note in `compose.yml`'s
   `frontend` service about why one is needed) and sign in with GitLab. The account behind the
   very first login becomes this org's Admin automatically.

## Upgrading

1. Bump `PLATFORM_VERSION` in `.env` to the new version.
2. `docker compose pull && docker compose up -d`.

Compose's default behavior (stop the old container, then start the replacement) already gives
single-version operation - nothing else to configure. Every migration this backend ships is
additive-only, so an in-place upgrade never requires a maintenance window for the schema itself;
sequential upgrades (one version at a time) are the supported, best-tested path. Rolling back is
just reverting `PLATFORM_VERSION` and re-running step 2 - never run a database downgrade against a
live install.

## Kubernetes / Helm

A v2 Helm chart is coming soon. Until then, `legacy-v1/charts/plumber` is the closest available
reference (it deploys v1, not v2 - the container images, environment variables, and data model are
different; do not point v1's chart at v2 images).

## Legacy v1

The previous install line (Helm chart, Docker Compose with bundled Traefik, podman, `install.sh`)
still lives, unchanged, in [`legacy-v1/`](legacy-v1/). See `legacy-v1/README.md` for what moved and
why.

## Contributions

You are welcome to help us improve this repository! Open an Issue or create a Pull Request from
your fork.
