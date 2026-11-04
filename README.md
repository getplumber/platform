# Self-Managed Plumber

[![Plumber Score](https://score.getplumber.io/github.com/getplumber/platform.svg)](https://score.getplumber.io/github.com/getplumber/platform)
[![CI](https://github.com/getplumber/platform/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/getplumber/platform/actions/workflows/ci.yml)
[![Release](https://github.com/getplumber/platform/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/getplumber/platform/actions/workflows/release.yml)

This project contains resources to setup a self-managed instance of [Plumber](https://getplumber.io/).

## Installation

- 🐳 **Docker Compose** — [Documentation](https://getplumber.io/docs/installation/docker-compose/)

  ```bash
  curl -fsSL https://raw.githubusercontent.com/getplumber/platform/main/install.sh | bash
  ```

- ☸️ **Kubernetes with Helm** — [Documentation](https://getplumber.io/docs/installation/kubernetes/)

## Contributions

You are welcome to help us improve this repository!

🎮 Open an Issue or create Pull Requests from your fork

### Changing GitHub workflows

Every action our workflows use is locked in `.github/workflows/actions.lock`: its commit, its owner and repository ids, and the actions it calls in turn. The `Lockfile` check fails a PR whose workflows the lockfile doesn't fully cover.

- After adding a workflow or changing any `uses:`, run `gh actions-lock` from the repository root (install it with `gh extension install github/gh-actions-lock`) and commit the updated lockfile with the workflow change.
- Never edit `actions.lock` by hand.
- Optional, before committing: `gh actions-lock --verify-local --no-fix` checks coverage offline. CI runs the full `gh actions-lock --verify`.
- Review a lockfile change as a dependency change: a changed `commit` is new code that will run, and a changed `owner_id` or `repo_id` means the repository behind the name is not the one we locked.
