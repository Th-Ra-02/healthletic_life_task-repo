#!/usr/bin/env bash
set -uo pipefail

LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "$LOG_FILE"; }
warn()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "$LOG_FILE" >&2; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }

log "Script started"
ENVIRONMENT=""
VERSION=""
IMAGE_REGISTRY=""

usage() {
  echo "Usage: $0 -e <environment> -v <version> -r <image_registry>"
  exit 1
}

while getopts "e:v:r:" opt; do
  case $opt in
    e) ENVIRONMENT="$OPTARG" ;;
    v) VERSION="$OPTARG" ;;
    r) IMAGE_REGISTRY="$OPTARG" ;;
    *) usage ;;
  esac
done

validate_inputs() {
  local failed=false

  if [ -z "$ENVIRONMENT" ]; then
    error "Missing required -e ENVIRONMENT"; failed=true
  elif [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    error "Invalid environment '${ENVIRONMENT}'. Must be dev, staging, or production."; failed=true
  fi

  if [ -z "$VERSION" ]; then
    error "Missing required -v VERSION"; failed=true
  fi

  if [ -z "$IMAGE_REGISTRY" ]; then
    error "Missing required -r IMAGE_REGISTRY"; failed=true
  fi

  if [ "$failed" = true ]; then
    error "Input validation failed. Aborting."
    usage
  fi

  log "Inputs valid: env=${ENVIRONMENT} version=${VERSION} registry=${IMAGE_REGISTRY}"
}

HELM_RELEASE="healthletic-backend"
K8S_NAMESPACE="healthletic"
DEPLOY_STARTED=false
PREVIOUS_REVISION=""

cleanup_and_rollback() {
  local exit_code=$?
  if [ $exit_code -ne 0 ] && [ "$DEPLOY_STARTED" = true ]; then
    error "Deployment failed. Attempting automatic rollback..."
    helm rollback "$HELM_RELEASE" "$PREVIOUS_REVISION" -n "$K8S_NAMESPACE" --wait \
      && log "Rollback succeeded." \
      || error "Rollback ALSO failed. Manual intervention required."
  fi
  log "Script finished with exit code ${exit_code}."
  exit $exit_code
}
trap cleanup_and_rollback EXIT INT TERM

retry() {
  local attempt=1
  local delay=5
  local description="$1"
  shift
  until "$@"; do
    if [ $attempt -ge 3 ]; then
      error "${description} failed after 3 attempts."
      return 1
    fi
    warn "${description} failed (attempt ${attempt}/3). Retrying in ${delay}s..."
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
  log "${description} succeeded."
}

main() {
  log "=== Starting deployment ==="
  validate_inputs

  local full_image="${IMAGE_REGISTRY}:${VERSION}"

  log "Recording current release revision (for rollback)..."
  PREVIOUS_REVISION=$(helm history "$HELM_RELEASE" -n "$K8S_NAMESPACE" \
    --max 1 -o json 2>/dev/null | grep -o '"revision":[0-9]*' | grep -o '[0-9]*' || echo "0")
  log "Previous revision: ${PREVIOUS_REVISION:-none}"

  DEPLOY_STARTED=true

  log "Deploying ${full_image} to '${ENVIRONMENT}'..."
  retry "Helm upgrade/install" helm upgrade --install "$HELM_RELEASE" "./helm/healthletic-backend" \
    --namespace "$K8S_NAMESPACE" --create-namespace \
    --set image.repository="$IMAGE_REGISTRY" \
    --set image.tag="$VERSION" \
    --wait --timeout 3m --atomic || exit 1

  log "Deployment of ${full_image} to ${ENVIRONMENT} completed successfully."
}

main
