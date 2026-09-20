# Helm chart: plumber-platform

Installs the [Plumber Platform](https://getplumber.io/) v2 (backend + frontend) on Kubernetes.
The previous product line keeps its own chart, `plumber` (see `legacy-v1/charts/plumber`); the two
are not compatible and do not share a database.

```bash
helm repo add plumber https://charts.getplumber.io/
helm repo update
helm upgrade --install plumber plumber/plumber-platform -n plumber --create-namespace -f values.yaml
```

## Minimal values

```yaml
platform:
  baseUrl: https://plumber.example.com     # public origin (also the OIDC audience)
  gitlabUrl: https://gitlab.example.com
  existingSecret: plumber-secrets          # key tokenEncryptionKey = openssl rand -hex 32
ingress:
  enabled: true
  className: nginx
  host: plumber.example.com                # one host: /api -> backend, / -> frontend
  tls:
    enabled: true
postgresql:
  deploy: true                             # or point custom.host at your own instance
  global:
    postgresql:
      auth:
        existingSecret: plumber-pg         # key password
redis:
  deploy: true
  auth:
    existingSecret: plumber-redis          # key password
```

Inline `platform.tokenEncryptionKey`, `postgresql.global.postgresql.auth.password` and
`redis.auth.password` are accepted for evaluation setups; the chart then writes them into the
Secret `<release>-plumber-platform`.

## First run

Create a GitLab OAuth application (redirect URI `<platform.baseUrl>/api/v1/auth/callback`,
confidential, scope `api`), then either run the command printed by `helm install` (NOTES), or let
the chart do it once with a post-install Job:

```yaml
bootstrap:
  enabled: true
  gitlabUrl: https://gitlab.example.com
  clientId: <application-id>
  scope: instance                          # or group + rootGroup
  existingSecret: plumber-bootstrap        # keys clientSecret, optional token
```

The Job waits for the backend, whose first boot can take a few minutes (image pull, migrations). Pass
`--timeout 15m` to `helm install` when `bootstrap.enabled` is true so Helm does not mark the release
failed while the Job is still waiting.

The Job waits for the backend `/readyz` (migrations run on the backend's first boot) and refuses an
already-configured instance, so it is safe to leave enabled.

## Operations

- Upgrade: bump `front.tag` and `backend.tag` together (every release pins both to one version),
  `helm upgrade`. The backend Deployment uses `Recreate` and one replica by design: the process owns
  the job queues, and two versions must never run at once. Rollback = roll the image back; never run
  a database downgrade.
- Private CA for GitLab: `customCertificateAuthority.{existingSecret|configMapName|certificates}`;
  the chart mounts it in both apps and builds the single PEM bundle the backend reads.
- Air-gapped: `platform.updateCheckUrl: "off"`.
- Probes: liveness `/healthz`, readiness `/readyz` (database-backed). Metrics: `/metrics` on the
  backend Service (not exposed by the ingress).

## Values

See `values.yaml`; every key is commented.
