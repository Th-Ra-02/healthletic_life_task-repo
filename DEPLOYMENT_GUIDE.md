# Deployment Guide — Healthletic Backend API

## How the GitHub Actions Workflow Works

The workflow (`.github/workflows/deploy.yml`) runs automatically on every
push to `main`, and on every pull request into `main` (build/scan only, no
deploy — so a PR can never touch the cluster).

It runs as a chain of jobs, each depending on the last:

1. **build** — builds the Docker image from the Dockerfile
2. **security_scan** — scans the image with Trivy; fails the pipeline on
   CRITICAL/HIGH vulnerabilities
3. **push** — pushes the image to Docker Hub (only on real pushes to `main`)
4. **deploy** — deploys to Kubernetes using the Helm chart at
   `./helm/healthletic-backend`
5. **smoke_tests** — checks the `/health` endpoint after deploying
6. **rollback** — automatically reverts the release if smoke tests fail

## Prerequisites

### Repository secrets (Settings → Secrets and variables → Actions)

| Secret | Purpose |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub account used to push the built image |
| `DOCKERHUB_TOKEN` | Docker Hub access token (created under Account Settings → Security — not your account password) |
| `KUBE_CONFIG_BASE64` | Your cluster's kubeconfig file, base64-encoded, so the workflow can authenticate to the cluster |

### Local tooling (for the manual deploy.sh script)

- `kubectl` — talks to the Kubernetes cluster
- `helm` — installs/upgrades the app on the cluster using the chart
- `docker` — builds the image locally
- A running cluster (a local `kind` cluster for testing, or a real cluster in production)

## How to Run the Manual Deployment Script
 
```bash
chmod +x deploy.sh
./deploy.sh -e <environment> -v <version> -r <image_registry>
```
 
**Required flags:**
 
| Flag | Description | Example |
|---|---|---|
| `-e` | Target environment: `dev`, `staging`, or `production` | `-e dev` |
| `-v` | Image version/tag to deploy | `-v latest` |
| `-r` | Registry + image path (no tag) | `-r docker.io/library/healthletic-backend` |
 
**Example (tested locally against a `kind` cluster):**
```bash
./deploy.sh -e dev -v latest -r docker.io/library/healthletic-backend
```
 
**What the script does, step by step:**
1. Validates all inputs (correct environment name, no missing flags) *before* touching anything
2. Records the current Helm release revision, so it knows what to roll back to if this deploy fails
3. Runs `helm upgrade --install` with `--wait --atomic`, retrying up to 3 times with increasing delays (5s, 10s, 20s) if it hits a transient failure
4. Logs every step, with timestamps, to `./logs/deploy_<timestamp>.log`
**Local testing note:** when testing against a local `kind` cluster, the
image needs to be loaded into the cluster manually first, since `kind`
can't reach Docker Hub for a private/unpublished image:
```bash
kind load docker-image healthletic-backend:latest --name healthletic-local
```
 
---
 
## Troubleshooting Common Failures
 
### Image push failures
 
- **`unauthorized: authentication required`** — `DOCKERHUB_USERNAME` or
  `DOCKERHUB_TOKEN` is missing or expired. Regenerate the token in Docker
  Hub and update the GitHub secret.
- **`denied: requested access to the resource is denied`** — the image
  repository doesn't exist under that account, or the token lacks write
  access. Create the repo on Docker Hub first.
### Helm deployment errors
 
- **`context deadline exceeded` (this happened during local testing)** —
  the pod never became healthy within the timeout. Diagnosed with:
```bash
  kubectl get pods -n healthletic
```
  In this case, the pod was stuck because Kubernetes defaults to *always
  pulling* an image tagged `:latest` from a remote registry — even if a
  matching image already exists locally. Since `healthletic-backend` isn't
  a real published image, that pull silently failed. **Fix:** add
  `imagePullPolicy: Never` to `templates/deployment.yaml`, which tells
  Kubernetes to only use images already loaded onto the node (correct for
  local `kind` testing; remove this line for a real registry in production).
- **`helm lint` fails** — check the specific error; both the workflow and
  `deploy.sh` stop before touching the cluster if this fails, so nothing
  gets deployed in a broken state.
- **Rollback reports `release: not found`** — not necessarily an error.
  If this was the very first deploy (no prior revision existed), Helm's
  own `--atomic` flag already auto-uninstalled the failed release before
  `deploy.sh`'s own rollback logic ran. Confirm the cluster is clean with
  `kubectl get pods -n <namespace>`.
### Smoke test / connectivity failures
 
- **`/health` unreachable** — pod may still be starting, or crash-looping.
  Check `kubectl get pods -n healthletic` and `kubectl logs <pod-name> -n healthletic`.
- **Port-forward fails with "address already in use"** — another local
  process is already using that port. Pick a different local port, e.g.:
```bash
  kubectl port-forward svc/healthletic-backend 8081:80 -n healthletic
```
  (the `80` on the right must stay as-is — that's the Service's actual
  port, defined in `values.yaml`; only the left-hand number is your choice)
 
---
 
## Rollback Procedures
 
### Automatic
- **Workflow:** the `rollback` job runs only if `smoke_tests` fails, and
  reverts to the previously recorded Helm revision.
- **`deploy.sh`:** a `trap` on script exit automatically attempts
  `helm rollback` if anything fails after the deploy begins.
### Manual
```bash
# View revision history
helm history healthletic-backend -n healthletic
 
# Roll back to a specific revision
helm rollback healthletic-backend <REVISION_NUMBER> -n healthletic --wait
 
# Confirm it worked
kubectl rollout status deployment/healthletic-backend -n healthletic
kubectl get pods -n healthletic -o wide
```
 
If a rollback itself fails, the safest recovery is to uninstall and
redeploy the last known-good version:
```bash
helm uninstall healthletic-backend -n healthletic
./deploy.sh -e <environment> -v <last_known_good_version> -r <registry>
```
