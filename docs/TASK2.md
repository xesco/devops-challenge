# Task 2: Deploy the Application

## Goal

Deploy the containerized Next.js application to a GKE Autopilot cluster,
reachable from the internet, serving live cryptocurrency prices.

---

## Files Created / Modified

| File                                          | Action | Summary                                    |
|-----------------------------------------------|--------|--------------------------------------------|
| `Dockerfile`                                  | Modify | Add `migrator` stage; copy `prisma.config.ts` |
| `terraform/versions.tf`                       | Create | Provider versions (google, github, kubernetes, random) |
| `terraform/variables.tf`                      | Create | Input variables (GCP + GitHub)              |
| `terraform/main.tf`                           | Create | GKE Autopilot + GCP API enablement (incl. sqladmin) |
| `terraform/artifact-registry.tf`              | Create | Docker image repository                    |
| `terraform/iam.tf`                            | Create | Deployer SA + role bindings                |
| `terraform/cloudsql.tf`                       | Create | Cloud SQL instance, database, user, cloudsql-client SA + key |
| `terraform/github.tf`                         | Create | Environment gate + repo secrets             |
| `terraform/outputs.tf`                        | Create | Cluster name + Cloud SQL instance connection name |
| `terraform/kubernetes.tf`                     | Create | K8s provider, namespace, `postgres-connection` + `cloudsql-credentials` secrets |
| `terraform/random.tf`                         | Create | Auto-generated PostgreSQL password + Cloud SQL instance name suffix |
| `terraform/terraform.tfvars.example`          | Create | Placeholder variable values                |
| `k8s/app/kustomization.yaml`                 | Create | Resource list, namespace, and image tag transformer (nextjs) |
| `k8s/app/deployment.yaml`                    | Create | App with probes, rolling update, security, Cloud SQL Auth Proxy sidecar |
| `k8s/app/service.yaml`                       | Create | LoadBalancer for external access           |
| `k8s/app/hpa.yaml`                           | Create | Horizontal pod autoscaler                  |
| `k8s/migration/job.yaml`                     | Create | Prisma migration Job with Cloud SQL Auth Proxy sidecar |
| `k8s/migration/kustomization.yaml`           | Create | Resource list, namespace, and image tag transformer (migrator) |
| `.github/workflows/release.yml`              | Create | Full pipeline: semantic versioning + build + migrate + deploy, all triggered on push to main |
| `.releaserc.json`                             | Create | semantic-release config (5 plugins)        |
| `scripts/prepare-release.sh`                 | Create | Updates `package.json` version field       |
| `CONTRIBUTING.md`                             | Create | Conventional commits guide                 |
| `Makefile`                                    | Modify | Add `migrate` target (calls `scripts/migrate.sh`) |
| `scripts/create.sh`                           | Create | Bootstrap infra (bucket + Terraform + creds) |
| `scripts/destroy.sh`                          | Create | Tear down infra and delete state bucket       |
| `scripts/migrate.sh`                          | Create | Run migration Job against live cluster (latest image or `TAG=`) |
| `scripts/cd-test-apply.sh`                    | Create | CD test: add Litecoin + mark heading         |
| `scripts/cd-test-revert.sh`                   | Create | CD test: remove Litecoin + revert heading    |
| `scripts/cd-test-k8s-apply.sh`                | Create | CD test: scale replicas + tighten probe      |
| `scripts/cd-test-k8s-revert.sh`               | Create | CD test: revert replicas + probe             |
| `.gitignore`                                  | Modify | Exclude Terraform state and .tfvars        |

---

## Key Decisions

### GKE Autopilot

Google manages nodes - no machine types, node pools, or OS patching. Pay per
pod request, not per node. Enforces security defaults: Workload Identity,
Shielded Nodes, resource requests required. Trade-off: no DaemonSets or
privileged containers (neither needed here).

### Artifact Registry over Docker Hub / GHCR

Same-region pulls over Google's internal network. No rate limits. IAM-based
access shared with GKE and CI/CD - no extra credential to manage.

### Service Account key for CI

SA `github-actions-deployer` with two roles: `artifactregistry.writer` (push
images) and `container.developer` (deploy workloads). Cannot modify cluster
config, IAM, or other GCP resources. JSON key created via Terraform, stored as
GitHub Actions secret (`GCP_SA_KEY`). Private key lives in local Terraform
state - acceptable for a demo.

**Production:** Workload Identity Federation (OIDC). GitHub Actions exchanges
its OIDC token for a short-lived GCP credential - no long-lived keys. Requires
~30 lines of Terraform (WI Pool, OIDC provider, SA binding scoped to repo).

### `migrator` Docker stage

The runner image has no Prisma CLI or migration files. A fourth stage branches
off `deps`, carries only `prisma/` and the CLI, runs `prisma migrate deploy`.

```
deps --> builder --> runner
  |
  └--> migrator
```

**Why a Job, not init container?** A Job runs once per deploy. An init container
runs once per pod - five replicas = five concurrent migrations (wasteful,
potential race). Job has `backoffLimit: 3` and reports success/failure clearly.

The migration Job has its own Cloud SQL Auth Proxy sidecar that provides the
database tunnel. No init container is needed — Cloud SQL is always available
once the proxy connects.

**`prisma.config.ts`:** Prisma 7 removed `url` from the schema's `datasource`
block. CLI commands now use `prisma.config.ts` (reads
`env("POSTGRES_PRISMA_URL")`). The migrator stage copies this file alongside
`prisma/`. The Job sets `POSTGRES_PRISMA_URL` from K8s secret refs.

### Cloud SQL for PostgreSQL

Managed Postgres (`db-f1-micro`, ZONAL, no HA) provisioned by Terraform.
Eliminates the in-cluster StatefulSet and PVC entirely. No node-local storage,
no postgres pod to manage or restart.

The app never connects directly to Cloud SQL. A **Cloud SQL Auth Proxy** sidecar
runs in each pod (nextjs Deployment and migration Job), opens a secure mTLS
tunnel to the Cloud SQL instance, and listens on `127.0.0.1:5432`. The main
container connects to localhost as if it were a local Postgres process.

The proxy authenticates using a `credentials.json` SA key mounted from the
`cloudsql-credentials` K8s Secret. The SA (`cloudsql-client`) has only
`roles/cloudsql.client` — it can open connections but cannot modify the
instance, change IAM, or access other GCP resources.

The migration Job proxy runs as a **native Kubernetes sidecar**
(`initContainers` with `restartPolicy: Always`, GKE 1.29+). Kubernetes
terminates it automatically once the main `migrator` container exits, so the
Job completes cleanly with no extra flags needed.

Cloud SQL instance names are globally reserved for 7 days after deletion. To
avoid recreation failures after `make destroy`, the instance name includes a
`random_id` suffix (`devops-challenge-<hex>`), so each fresh `make create` gets
a new unique name.

**Previous approach (replaced):** in-cluster StatefulSet + PVC + NetworkPolicy.
Simpler manifest-wise but no managed backups, no HA path, and postgres pod
restarts cause downtime.

### Terraform-managed Kubernetes Secrets

Two secrets created by Terraform:

- **`postgres-connection`** — `POSTGRES_PRISMA_URL` (full connection string
  pointing to `127.0.0.1:5432`) and `INSTANCE_CONNECTION_NAME` (injected into
  the proxy sidecar's args). Password auto-generated via `random_password`
  (32-char alphanumeric, `special = false` to avoid URL-encoding issues).
- **`cloudsql-credentials`** — `credentials.json` SA key for the Auth Proxy
  sidecar. Mounted read-only at `/secrets/cloudsql/`.

No manual secret creation, no human-chosen passwords. GKE encrypts secrets at
rest in etcd.

**Production:** GCP Secret Manager + Secrets Store CSI Driver. Secrets mounted
as tmpfs, never stored as K8s objects. Per-secret IAM, audit logging, rotation.

### LoadBalancer Service (HTTP on port 80)

Provisions a GCP Network Load Balancer directly - no controller, no domain, no
certificate wait. Immediately reachable at the external IP.

**Production:** GKE Gateway API with Google-managed TLS, HTTP->HTTPS redirect,
custom domain. Next.js Service changes to ClusterIP.

### Kustomize over Helm

Built into `kubectl`, no extra tooling. Manifests are valid YAML usable
with plain `kubectl apply -f`. Simpler than Go templates for a
single-environment project. Two flat directories (`k8s/app/` and
`k8s/migration/`) — CI/CD uses `kustomize edit set image` to inject the
versioned Artifact Registry image at deploy time.

### GitHub Actions CI/CD

A single workflow (`release.yml`) handles the full release and deploy lifecycle
on every push to `main`.

**Concurrency control:** The workflow uses a `concurrency` group
(`release-${{ github.ref }}`) with `cancel-in-progress: false`. Multiple pushes
to `main` are queued and run sequentially — each release completes fully
(release → build → migrate → deploy) before the next one starts. This prevents
race conditions in semantic-release tag creation, migration Job conflicts, and
out-of-order deployments.

**`release.yml`** uses [semantic-release](https://semantic-release.gitbook.io/)
to analyze commit messages (Conventional Commits). A `feat:` commit bumps the
minor version, a `fix:` bumps the patch, `BREAKING CHANGE:` bumps major,
`chore:` produces no release. When a release is triggered, it: updates
`package.json` via `scripts/prepare-release.sh`, commits back with
`chore(release): vX.Y.Z [skip ci]`, creates a GitHub release with
auto-generated release notes, and pushes a `vX.Y.Z` tag. Three downstream
jobs then run automatically with `needs: release`:

1. **build** — authenticates to GCP, builds two images tagged `v1.2.3`:
   `nextjs` (runner stage) and `migrator` (migrator stage), pushes both
   to Artifact Registry.
2. **migrate** — patches the migration kustomization with the new migrator
   image, deletes any previous `prisma-migrate` Job (avoids immutability
   conflicts), applies the Job, waits up to 120s for completion.
3. **deploy** — patches the app kustomization with the new `v1.2.3` tag,
   applies manifests, waits for the rollout.

`chore:` commits push to `main` but never trigger a release or deploy. Images
are tagged with the semantic version (`v1.2.3`), not a git SHA.

The workflow uses `GH_PAT` (a classic PAT with `repo` scope) instead of the
default `GITHUB_TOKEN` so that the semantic-release tag push can be seen by
subsequent job steps. `GCP_SA_KEY` and `GCP_PROJECT_ID` are provisioned by
Terraform.

### Makefile

Infra lifecycle, convenience, and CD testing. `create` and `destroy` call
scripts that handle the full lifecycle: prereq checks, GCS bucket management,
Terraform init/apply/destroy, GKE credentials. `show-ip` prints the external
LoadBalancer IP. `migrate` runs the migration Job manually against the live
cluster — useful after a Cloud SQL swap or when no migration files changed (so
`migrate.yaml` didn't trigger). Default: latest migrator image from Artifact
Registry; override with `make migrate TAG=<tag>`.

`cd-test-apply`/`cd-test-revert` exercise the full CD pipeline: create a
Prisma migration (insert/delete test currency), change heading, commit, push.
Pipeline builds new images, runs migrations, and deploys automatically.
All cd-test scripts check for dirty working tree first.

All four `cd-test-*` targets accept `ARGS=-d` (or `ARGS=--dry-run`) to preview
changes without committing or pushing. Dry run applies changes temporarily,
shows `git diff --cached`, then reverts everything:

```bash
make cd-test-apply ARGS=-d       # preview changes
make cd-test-apply               # commit and push (triggers CD)
```

---

## Application Configuration

### Next.js Deployment

- 2 replicas minimum (survives restarts and rolling updates)
- Readiness probe: `httpGet /readyz` port 3000 (DB-aware: `SELECT 1` ping,
  returns 503 if DB unreachable — pod leaves rotation until DB recovers)
- Liveness probe: `tcpSocket` port 3000, `periodSeconds: 10`,
  `timeoutSeconds: 3`, `failureThreshold: 3` (tolerates transient DB hiccups —
  TCP check avoids killing pods due to DB outages)
- Startup probe: `httpGet /healthz` port 3000, `periodSeconds: 5`,
  `failureThreshold: 12` (up to 60s for cold start; shallow check, no DB)
- Rolling update: `maxSurge: 1`, `maxUnavailable: 0` (zero-downtime)
- Resources: 250m CPU / 512Mi memory requests, 1000m / 512Mi limits
- Security: `runAsUser: 1001`, `runAsNonRoot`, `readOnlyRootFilesystem`,
  `allowPrivilegeEscalation: false`, `drop: [ALL]` (`.next/cache` via emptyDir)
- Topology spread: `maxSkew: 1` across nodes
- HPA: 2-5 replicas on 70% CPU
- PDB: `minAvailable: 1` (availability during voluntary disruptions)
- Cloud SQL Auth Proxy sidecar: `gcr.io/cloud-sql-connectors/cloud-sql-proxy:2`,
  50m CPU / 64Mi memory requests, credentials from `cloudsql-credentials` secret

### Cloud SQL Auth Proxy sidecar

Present in both the nextjs Deployment and the migration Job pod. Args:
`--structured-logs --port=5432 <INSTANCE_CONNECTION_NAME>`.

In the **nextjs Deployment** the proxy runs as a regular container alongside
the app container.

In the **migration Job** the proxy runs as a **native Kubernetes sidecar**
(`initContainers` with `restartPolicy: Always`). Kubernetes terminates it
automatically when the main `migrator` container exits — no
`--exit-zero-on-sigterm` flag needed, and the Job completes cleanly.

### Connection string

`POSTGRES_PRISMA_URL` used by both app runtime and Prisma CLI. Sourced from the
`postgres-connection` K8s Secret in both the Deployment and migration Job:

```
postgres://postgres:<password>@127.0.0.1:5432/currencies?schema=public
```

`127.0.0.1:5432` is the Cloud SQL Auth Proxy sidecar listening locally in each
pod. The sidecar routes traffic to the Cloud SQL instance over a secure mTLS
tunnel.

---

## Terraform

GCS backend with versioning. State bucket (`<PROJECT_ID>-tfstate`) created by
`create.sh` before `terraform init` (can't be managed by the same config that
uses it). Versioning provides state history and recovery.

Resources (GCP - `hashicorp/google`):
- API enablement (`container`, `artifactregistry`, `iam`, `sqladmin`)
- GKE Autopilot cluster (regional, `REGULAR` release channel, default VPC)
- Artifact Registry (Docker, same region)
- Deployer SA with `artifactregistry.writer` + `container.developer`
- Deployer SA key (`google_service_account_key`, private key in state)
- Cloud SQL instance (`db-f1-micro`, ZONAL, Postgres 17, `random_id` name suffix)
- Cloud SQL database (`currencies`) and user (`postgres`)
- `cloudsql-client` SA with `roles/cloudsql.client` + SA key

Resources (GitHub - `integrations/github`):
- `GCP_SA_KEY` and `GCP_PROJECT_ID` repo secrets

Resources (Kubernetes - `hashicorp/kubernetes`):
- `moonpay` namespace
- `postgres-connection` secret (full `POSTGRES_PRISMA_URL` + `INSTANCE_CONNECTION_NAME`)
- `cloudsql-credentials` secret (SA key JSON for the Auth Proxy sidecar)

Resources (Random - `hashicorp/random`):
- 32-char alphanumeric password (`special = false` for URL safety)
- 4-byte hex suffix for Cloud SQL instance name (avoids 7-day name reservation)

K8s provider authenticates via GKE endpoint + `google_client_config` token.
GitHub provider uses `GITHUB_TOKEN` env var (`export GITHUB_TOKEN=$(gh auth
token)` before plan/apply). All variables have validation blocks.

---

## `.gitignore` additions

```
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.backup
terraform/*.tfvars
!terraform/terraform.tfvars.example
```

---

## Security Summary

- No secrets in source control (K8s Secrets via Terraform with auto-generated
  password, `.tfvars` gitignored, no credentials at build time)
- Non-root containers with read-only filesystem, `allowPrivilegeEscalation:
  false`, `drop: [ALL]` on all containers
- Least-privilege IAM: deployer SA has two roles only; `cloudsql-client` SA has
  `roles/cloudsql.client` only — cannot modify the instance or access other resources
- Database unreachable from the public internet; Cloud SQL Auth Proxy + IAM
  controls access (no NetworkPolicy needed — there is no in-cluster postgres pod)
- Images tagged with semantic version (`v1.2.3`) for provenance and traceability
- All pods declare resource requests and limits
- PDB ensures availability during voluntary disruptions
- `chore:` commits never trigger a release or deploy — only intentional `feat:`/`fix:` changes reach the cluster
