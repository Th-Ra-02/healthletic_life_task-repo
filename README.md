# Healthletic Backend API

A Flask-based backend API for Healthletic Lifestyle, with a full CI/CD
pipeline for automated build, security scanning, testing, and deployment
to Kubernetes.
 
## What's in this repo
 
| File / Folder | Purpose |
|---|---|
| `app.py` | The Flask API (`/health`, `/health/db`, `/api/v1/workouts`) |
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Multi-stage build for the app's container image |
| `helm/healthletic-backend/` | Helm chart describing how to run the app on Kubernetes |
| `.github/workflows/deploy.yml` | GitHub Actions pipeline: build → scan → push → deploy → test → rollback |
| `deploy.sh` | Manual deployment script for local/on-demand deploys |
| `DEPLOYMENT_GUIDE.md` | Full guide: prerequisites, running the pipeline/script, troubleshooting, rollback |
 
## Quick start (local)
 
```bash
pip install -r requirements.txt
python3 app.py
```
 
## Quick start (Docker)
 
```bash
docker build -t healthletic-backend:latest .
docker run -d -p 5000:5000 healthletic-backend:latest
curl localhost:5000/health
```
 
## Deploying
 
See [`DEPLOYMENT_GUIDE.md`](./DEPLOYMENT_GUIDE.md) for full details on the
CI/CD pipeline, required secrets, the manual `deploy.sh` script, and
troubleshooting.
