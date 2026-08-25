# Plumber v1 (legacy)

The v1 self-managed line lives here, **unchanged**. Everything under this directory (`compose.yml`,
`compose.local.yml`, `.env.example`, `.env.local.example`, `configmap.yml.example`,
`configmap.local.yml.example`, `podman.yml.example`, `podman.local.yml.example`, `.docker/`,
`charts/`, `install.sh`, `scripts/`, `versions.env`) is exactly what used to live at the repository
root, moved here as a unit on 2026-08-25 when v2 took over the root layout (compose-first, see the
root `README.md`). Nothing inside this directory was edited as part of that move: every script's
own relative references (`compose.yml`, `versions.env`, `scripts/*.sh`) still resolve, because the
whole set moved together.

## Why v1 still lives here

v1 (the Helm/Compose/podman install described here) is still supported for existing installs. It is
not being deprecated by this move, only relocated so the repository root can carry the new v2 line
(a different product generation, incompatible configuration, `docker.io/getplumber/platform-*`
images instead of v1's own). Run v1 exactly as documented below, from inside this directory.

## Installing v1

- **Docker Compose**:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/getplumber/platform/main/legacy-v1/install.sh | bash
  ```

- **Kubernetes with Helm**: see `charts/plumber/README.md` in this directory.

- **Podman**: see `podman.yml.example` / `podman.local.yml.example` in this directory, and
  `scripts/backup_podman.sh` / `scripts/restore_podman.sh`.

## A note on documentation links

The public docs site (getplumber.io/docs/installation/...) linked v1's Compose/Helm instructions
at their old repository-root paths. **Those links now need the `legacy-v1/` path prefix** (e.g. a
raw-file link to `install.sh` becomes `.../platform/main/legacy-v1/install.sh`, a link into
`charts/plumber` becomes `.../platform/main/legacy-v1/charts/plumber`). This directory does not fix
the site itself; whoever owns getplumber.io's docs content needs to update those links separately.

## Upgrading within v1

Nothing about v1's own upgrade story changed: `scripts/update.sh` still reads `versions.env` from
this directory and syncs image tags into your `.env`, exactly as before the move.

## v2

For the new install line, see the repository root `README.md`.
