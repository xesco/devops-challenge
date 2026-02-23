# Environment Setup

Steps to get this project running locally from scratch.

## Prerequisites

- [mise](https://mise.jdx.dev/) - manages Node 22 and pnpm versions
- [Docker](https://docs.docker.com/engine/install/) - runs PostgreSQL 17

---

## 1. Install mise

```bash
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
mise trust
source ~/.bashrc
```

## 2. Install Node 22 + pnpm via mise

`mise.toml` declares `node = "lts"` and `pnpm = "latest"`:

```bash
mise install
```

## 3. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

## 4. Create .env

```bash
cp .env.example .env
```

Defaults match the docker-compose Postgres service - no edits needed.

## 5. Install dependencies

```bash
pnpm install
```

Also runs `prisma generate` via the `postinstall` hook.

## 6. Start PostgreSQL

```bash
docker compose up -d postgres
```

## 7. Run migrations

```bash
pnpm db:migrate
```

## 8. Start the dev server

```bash
pnpm dev
```

App available at <http://localhost:3000>.

---

## Subsequent runs

```bash
docker compose up -d postgres
pnpm dev
```

---

## GCP Setup (Deployment)

Required for Task 2. Skip if you only need local development.

### 9. Install gcloud CLI

**macOS (Homebrew):**

```bash
brew install --cask google-cloud-sdk
```

**ARM64 (Raspberry Pi):**

```bash
curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm.tar.gz | tar -xz -C ~
~/google-cloud-sdk/install.sh --path-update true
source ~/.bashrc
```

**x86_64:**

```bash
curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz | tar -xz -C ~
~/google-cloud-sdk/install.sh --path-update true
source ~/.bashrc
```

### 10. Install kubectl

```bash
gcloud components install kubectl
```

After cluster creation (step 18), verify version compatibility:

```bash
kubectl version
```

Client should be within one minor version of the server (K8s version skew policy).

### 11. Install Terraform and Kustomize

```bash
mise use -g terraform@latest
mise use -g kustomize@latest
```

### 12. Authenticate

```bash
gcloud auth login
```

### 13. Create or select a GCP project

**New project:**

```bash
gcloud projects create <PROJECT_ID> --name="<Display Name>"
gcloud config set project <PROJECT_ID>
```

Project ID must be globally unique, 6-30 chars, lowercase + digits + hyphens.

**Existing project:**

```bash
gcloud projects list
gcloud config set project <PROJECT_ID>
```

### 14. Link billing

Required for GKE, Artifact Registry, and other paid services.

```bash
gcloud billing accounts list
gcloud billing projects link <PROJECT_ID> --billing-account=<BILLING_ACCOUNT_ID>
```

### 15. Application Default Credentials

Used by Terraform to authenticate with GCP.

```bash
gcloud auth application-default login
```

### 16. Configure Terraform variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

- `project_id` - your GCP project ID
- `region` - GCP region (default `us-central1`)
- `github_owner` - your GitHub username or organization
- `github_repository` - repo name (without owner prefix)
- `github_reviewers` - GitHub usernames who can approve production deploys

### 17. Authenticate GitHub CLI

Terraform GitHub provider needs a token for repo environment and secrets.

```bash
mise use -g gh@latest
gh auth login
export GITHUB_TOKEN=$(gh auth token)
```

> `GITHUB_TOKEN` must be exported before every `terraform plan`/`apply`.

### 18. Provision infrastructure

```bash
make create
```

This runs `scripts/create.sh`:

1. Checks prerequisites (`gcloud`, `terraform`, `gh`; `terraform.tfvars` exists)
2. Reads `PROJECT_ID` and `REGION` from `gcloud config`
3. Exports `GITHUB_TOKEN` from `gh auth token`
4. Creates GCS state bucket (`gs://<PROJECT_ID>-tfstate`) with versioning +
   public-access prevention (idempotent - skips if exists)
5. `terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"`
6. `terraform apply -auto-approve`
7. Fetches GKE credentials via `gcloud container clusters get-credentials`

Creates: GKE Autopilot cluster (~10 min), Cloud SQL for PostgreSQL instance
(~5 min, `db-f1-micro` ZONAL), Artifact Registry, deployer SA + IAM roles,
`cloudsql-client` SA with `roles/cloudsql.client`, GitHub `production`
environment (approval gate), repo secrets (`GCP_SA_KEY`, `GCP_PROJECT_ID`),
K8s `moonpay` namespace, K8s `postgres-connection` secret (full connection
string + instance connection name), K8s `cloudsql-credentials` secret (SA key
JSON for the Auth Proxy sidecar).

Verify: `kubectl cluster-info`

### 19. Deploy

A single GitHub Actions workflow (`release.yml`) handles the full release and
deploy lifecycle on every push to `main`.

**`release.yml`** — triggered on every push to `main`. Analyzes commit messages
using [Conventional Commits](https://www.conventionalcommits.org/). If a
releasable commit (`feat:`, `fix:`, etc.) is found, it updates `package.json`,
creates a GitHub release, and pushes a version tag (`v1.2.3`). See
`CONTRIBUTING.md` for the commit format. Three downstream jobs then run
automatically:

1. **build** — builds and pushes two images to Artifact Registry:
   - `…/nextjs:v1.2.3` (app, runner stage)
   - `…/nextjs:migrator-v1.2.3` (Prisma CLI, migrator stage)
2. **migrate** — applies and waits for the migration Job to complete (fully
   automatic, no approval required)
3. **deploy** — applies K8s manifests and waits for the rollout (fully
   automatic, no approval gate)

**Full flow:** push a `feat:` or `fix:` commit → `release.yml` cuts `v1.2.3`
→ builds images → migrates → deploys. No manual intervention required.

`chore:` commits (e.g. config tweaks) never trigger a release or deploy.

Multiple pushes to `main` are serialized via a concurrency group — each
pipeline completes fully before the next starts.

To run a migration manually (e.g. after a fresh Cloud SQL instance):

```bash
make migrate           # latest migrator image
make migrate SHA=<sha> # pin to a specific image
```

> **ARM64 note:** Local Docker builds on Raspberry Pi produce ARM64 images,
> incompatible with GKE (x86_64). CI runs on `ubuntu-latest` (x86_64) - handled
> automatically.

#### Manual operations

Releases and deploys happen automatically on push to `main` via CI. For infra
lifecycle:

```bash
make create     # Provision GKE cluster + all infrastructure
make destroy    # Tear everything down
```

### 20. Verify

```bash
make show-ip                     # Get external IP (may take a minute after first deploy)
curl http://<EXTERNAL-IP>        # Should return cryptocurrency prices page
```

### 21. CD pipeline test (optional)

To exercise the full pipeline end-to-end, use a `feat:` commit to trigger a
release and deploy:

```bash
make cd-test-apply ARGS=-d  # Preview changes (dry run, no commit/push)
make cd-test-apply           # Adds Litecoin currency + marks heading "(CD Test)"
```

This commits with `feat: CD test: add Litecoin and mark heading` and pushes to
`main`. `release.yml` cuts a new minor release, builds images, runs migrations,
and deploys — all automatically.

```bash
make cd-test-revert ARGS=-d # Preview revert (dry run)
make cd-test-revert         # Removes Litecoin + reverts heading
```

Same flow. App returns to original state (3 currencies) with no manual steps.

### 22. Teardown

```bash
make destroy
```

Runs `scripts/destroy.sh`:

1. Checks prerequisites (`gcloud`, `terraform`, `gh`)
2. Exports `GITHUB_TOKEN` from `gh auth token`
3. `terraform destroy -auto-approve`
4. Deletes GCS state bucket

Destroys: GKE cluster, Cloud SQL instance (data lost), Artifact Registry, SAs,
GitHub environment + secrets, K8s namespace + secrets. Migration re-seeds data
on next deploy.

To bring everything back: `make create` then push to `main`.
