#!/usr/bin/env bash
set -euo pipefail

# One-command 3-Node Kind Kubernetes setup, deployment, and verification (ID: 68130677)
# Target: Linux Ubuntu (20.04 / 22.04 / 24.04) & macOS with Docker Engine

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLUSTER_NAME="k8s-68130677"
KUBE_CONTEXT="kind-${CLUSTER_NAME}"
NAMESPACE="iam-68130677"
KIND_VERSION="v0.24.0"
INGRESS_KIND_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml"
LOG_FILE="${SCRIPT_DIR}/verification-log.txt"
DOMAINS=("www.iam-68130677.com" "www.id-68130677.com" "admin.iam-68130677.com")
APP_DEPLOYMENTS=("portal-68130677" "app-research" "api-68130677" "admin-68130677")

step() {
  echo ""
  echo "============================================================"
  echo " $1"
  echo "============================================================"
}

fail() {
  echo "" >&2
  echo "[ERROR] $1" >&2
  exit 1
}

detect_os_arch() {
  local uname_s uname_m
  uname_s="$(uname -s | tr '[:upper:]' '[:lower:]')"
  uname_m="$(uname -m)"
  case "$uname_s" in
    linux|darwin) OS_NAME="$uname_s" ;;
    *) fail "Unsupported OS: $uname_s" ;;
  esac
  case "$uname_m" in
    x86_64|amd64) ARCH_NAME="amd64" ;;
    aarch64|arm64) ARCH_NAME="arm64" ;;
    *) fail "Unsupported CPU architecture: $uname_m" ;;
  esac
}

ensure_kind() {
  if command -v kind >/dev/null 2>&1; then
    KIND_BIN="$(command -v kind)"
    return
  fi
  mkdir -p "${SCRIPT_DIR}/bin"
  KIND_BIN="${SCRIPT_DIR}/bin/kind"
  if [[ -x "$KIND_BIN" ]]; then
    return
  fi
  local url="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS_NAME}-${ARCH_NAME}"
  echo "kind CLI not found. Downloading official kind ${KIND_VERSION} (${OS_NAME}/${ARCH_NAME}) to ./bin/kind ..."
  curl -fsSL -o "$KIND_BIN" "$url" || fail "Failed to download kind from $url"
  chmod +x "$KIND_BIN"
  echo "[OK] Downloaded kind to $KIND_BIN"
}

ensure_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    KUBECTL_BIN="$(command -v kubectl)"
    return
  fi
  mkdir -p "${SCRIPT_DIR}/bin"
  KUBECTL_BIN="${SCRIPT_DIR}/bin/kubectl"
  if [[ -x "$KUBECTL_BIN" ]]; then
    return
  fi
  echo "kubectl not found. Downloading latest stable kubectl (${OS_NAME}/${ARCH_NAME}) to ./bin/kubectl ..."
  local kver
  kver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" || fail "Failed to determine stable kubectl version."
  curl -fsSL -o "$KUBECTL_BIN" "https://dl.k8s.io/release/${kver}/bin/${OS_NAME}/${ARCH_NAME}/kubectl" \
    || fail "Failed to download kubectl ${kver}."
  chmod +x "$KUBECTL_BIN"
  echo "[OK] Downloaded kubectl ${kver} to $KUBECTL_BIN"
}

ensure_linux_inotify() {
  if [[ "$OS_NAME" != "linux" ]]; then
    return
  fi
  local cur_watches cur_instances
  cur_watches="$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)"
  cur_instances="$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)"
  if [[ "$cur_watches" -lt 524288 || "$cur_instances" -lt 512 ]]; then
    echo "Raising Linux inotify limits for 3-node Kind stability (watches=${cur_watches}->524288, instances=${cur_instances}->512)..."
    if [[ "$(id -u)" -eq 0 ]]; then
      sysctl -w fs.inotify.max_user_watches=524288 >/dev/null || true
      sysctl -w fs.inotify.max_user_instances=512 >/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
      sudo sysctl -w fs.inotify.max_user_watches=524288 >/dev/null || true
      sudo sysctl -w fs.inotify.max_user_instances=512 >/dev/null || true
    fi
  else
    echo "[OK] Linux inotify limits are sufficient (watches=${cur_watches}, instances=${cur_instances})."
  fi
}

ensure_hosts_entries() {
  local missing=()
  local d
  for d in "${DOMAINS[@]}"; do
    if ! grep -Eq "^[[:space:]]*127\.0\.0\.1[[:space:]]+[^#]*\b${d//./\\.}\b" /etc/hosts; then
      missing+=("127.0.0.1 ${d}")
    fi
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    echo "[OK] /etc/hosts already maps 127.0.0.1 for all 3 required domains."
    return
  fi

  echo "Adding missing domain entries to /etc/hosts (may prompt for sudo password)..."
  local line
  for line in "${missing[@]}"; do
    if [[ "$(id -u)" -eq 0 ]]; then
      printf '%s\n' "$line" >> /etc/hosts
    else
      printf '%s\n' "$line" | sudo tee -a /etc/hosts >/dev/null
    fi
  done
  echo "[OK] Updated /etc/hosts."
}

# ============================================================
# STEP 1: Prerequisites & Ubuntu System Tuning
# ============================================================
step "[1/8] Checking Prerequisites (Docker, curl, kind, kubectl)"

detect_os_arch

command -v curl >/dev/null 2>&1 || fail "curl is not installed. Run: sudo apt-get update && sudo apt-get install -y curl"
command -v docker >/dev/null 2>&1 || fail "docker is not installed. Install Docker Engine on Ubuntu first."

if ! docker info >/dev/null 2>&1; then
  fail "Cannot connect to Docker daemon. Make sure Docker is running (sudo systemctl start docker) and your user has permission (sudo usermod -aG docker \$USER && newgrp docker)."
fi

ensure_kind
ensure_kubectl
ensure_linux_inotify
echo "[OK] OS=${OS_NAME}/${ARCH_NAME} | kind=${KIND_BIN} | kubectl=${KUBECTL_BIN}"

# ============================================================
# STEP 2: Configure /etc/hosts
# ============================================================
step "[2/8] Configuring /etc/hosts"
ensure_hosts_entries

# ============================================================
# STEP 3: Create / Reuse 3-Node Kind Cluster
# ============================================================
step "[3/8] Creating 3-Node Kind Kubernetes Cluster (${CLUSTER_NAME})"

if "$KIND_BIN" get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "[OK] Kind cluster '${CLUSTER_NAME}' already exists. Reusing existing 3-node cluster."
else
  if command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -Eq ':80[[:space:]]'; then
    echo "[WARNING] Port 80 appears to be in use. If cluster creation fails, stop nginx/apache2 (sudo systemctl stop apache2 nginx)."
  fi
  echo "Creating 3-node cluster from kind-config.yaml (1 control-plane + 2 workers)..."
  "$KIND_BIN" create cluster --config kind-config.yaml || fail "Failed to create Kind cluster '${CLUSTER_NAME}'."
fi

"$KUBECTL_BIN" config use-context "${KUBE_CONTEXT}" >/dev/null
echo "Waiting for all 3 nodes to become Ready..."
"$KUBECTL_BIN" wait --for=condition=Ready nodes --all --timeout=180s

NODE_COUNT="$("$KUBECTL_BIN" get nodes --no-headers | wc -l | tr -d ' ')"
echo "[OK] Cluster active with ${NODE_COUNT} nodes:"
"$KUBECTL_BIN" get nodes -o wide
if [[ "$NODE_COUNT" -ne 3 ]]; then
  fail "Expected 3 Kubernetes nodes, but found ${NODE_COUNT}."
fi

# ============================================================
# STEP 4: Build Local Docker Images & Load into Kind Cluster
# ============================================================
step "[4/8] Building Local Images and Loading into Kind 3-Node Cluster"

docker build -t portal-68130677:1.0 apps/portal-68130677
docker build -t app-research:1.0    apps/app-research
docker build -t api-68130677:1.0    apps/api-68130677
docker build -t admin-68130677:1.0  apps/admin-68130677

if ! docker image inspect postgres:16-alpine >/dev/null 2>&1; then
  docker pull postgres:16-alpine
fi

echo "Loading all 5 images into Kind cluster '${CLUSTER_NAME}'..."
for img in portal-68130677:1.0 app-research:1.0 api-68130677:1.0 admin-68130677:1.0; do
  "$KIND_BIN" load docker-image "$img" --name "${CLUSTER_NAME}"
done
echo "[OK] All 5 images loaded into Kind cluster nodes."

# ============================================================
# STEP 5: Install NGINX Ingress Controller (Kind Provider)
# ============================================================
step "[5/8] Ensuring NGINX Ingress Controller (Kind Provider) is Ready"

if ! "$KUBECTL_BIN" get namespace ingress-nginx >/dev/null 2>&1; then
  echo "Installing ingress-nginx controller for Kind..."
  "$KUBECTL_BIN" apply -f "${INGRESS_KIND_URL}"
else
  echo "[OK] ingress-nginx namespace already exists."
fi

echo "Waiting for ingress-nginx controller pod to become Ready..."
"$KUBECTL_BIN" wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
echo "[OK] NGINX Ingress Controller is Ready."

# ============================================================
# STEP 6: Apply Manifests (PostgreSQL First, then 4 Apps & Ingress)
# ============================================================
step "[6/8] Applying Kubernetes Manifests (Namespace, DB, 4 Apps, Ingress)"

EXISTING_DEPS=()
for dep in "${APP_DEPLOYMENTS[@]}"; do
  if "$KUBECTL_BIN" get deployment "$dep" -n "${NAMESPACE}" >/dev/null 2>&1; then
    EXISTING_DEPS+=("$dep")
  fi
done

"$KUBECTL_BIN" apply -f k8s/00-namespace.yaml -f k8s/01-config-secret.yaml -f k8s/02-postgres.yaml
echo "Waiting for PostgreSQL (postgres-68130677) to become Ready..."
"$KUBECTL_BIN" rollout status deployment/postgres-68130677 -n "${NAMESPACE}" --timeout=180s

"$KUBECTL_BIN" apply -f k8s/03-portal.yaml -f k8s/04-research.yaml -f k8s/05-api.yaml -f k8s/06-admin.yaml

INGRESS_APPLIED=0
for attempt in $(seq 1 12); do
  if "$KUBECTL_BIN" apply -f k8s/07-ingress.yaml; then
    INGRESS_APPLIED=1
    break
  fi
  echo "Waiting for ingress-nginx admission webhook (attempt ${attempt}/12)..."
  sleep 5
done
if [[ "$INGRESS_APPLIED" -ne 1 ]]; then
  fail "Failed to apply k8s/07-ingress.yaml after 12 attempts."
fi

if [[ "${#EXISTING_DEPS[@]}" -gt 0 ]]; then
  for dep in "${EXISTING_DEPS[@]}"; do
    echo "Restarting existing deployment/${dep} to load freshly built image..."
    "$KUBECTL_BIN" rollout restart "deployment/${dep}" -n "${NAMESPACE}" >/dev/null
  done
fi

# ============================================================
# STEP 7: Wait for Rollout & Ingress Endpoint Warmup
# ============================================================
step "[7/8] Waiting for All 4 Application Deployments & Ingress Sync"

for dep in "${APP_DEPLOYMENTS[@]}"; do
  "$KUBECTL_BIN" rollout status "deployment/${dep}" -n "${NAMESPACE}" --timeout=150s
done

WARMUP_URLS=(
  "http://www.iam-68130677.com/"
  "http://www.id-68130677.com/"
  "http://www.iam-68130677.com/research"
  "http://www.iam-68130677.com/api-68130677/Hello"
  "http://admin.iam-68130677.com/"
)
echo "Waiting for NGINX Ingress to sync all endpoints..."
HTTP_READY=0
for _ in $(seq 1 20); do
  ALL_OK=1
  for u in "${WARMUP_URLS[@]}"; do
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$u" || true)"
    if [[ "$code" != "200" ]]; then
      ALL_OK=0
      break
    fi
  done
  if [[ "$ALL_OK" -eq 1 ]]; then
    HTTP_READY=1
    break
  fi
  sleep 2
done
if [[ "$HTTP_READY" -ne 1 ]]; then
  echo "[WARNING] Not all endpoints returned HTTP 200 within 40s; proceeding to diagnostics."
fi

# ============================================================
# STEP 8: Automated Verification & Evidence Log
# ============================================================
step "[8/8] 3-Node Cluster & HTTP Endpoint Verification"

NODES_OUT="$("$KUBECTL_BIN" get nodes -o wide 2>&1)"
GET_OUT="$("$KUBECTL_BIN" get all,pvc,ingress -n "${NAMESPACE}" -o wide 2>&1)"
DESC_OUT="$("$KUBECTL_BIN" describe ingress ingress-public ingress-admin -n "${NAMESPACE}" 2>&1)"

echo "$NODES_OUT"
echo ""
echo "$GET_OUT"
echo ""
echo "--- HTTP Endpoint Verification ---"

CHECKS=(
  "200|http://www.iam-68130677.com/|portal-68130677 (www.iam)"
  "200|http://www.id-68130677.com/|portal-68130677 (www.id alias)"
  "200|http://www.iam-68130677.com/photo|portal-68130677 (/photo from PostgreSQL)"
  "200|http://www.iam-68130677.com/research|app-research (/research)"
  "200|http://www.id-68130677.com/research|app-research (www.id /research)"
  "200|http://www.iam-68130677.com/api-68130677/Hello|api-68130677 (/api-68130677/Hello)"
  "200|http://admin.iam-68130677.com/|admin-68130677 (dashboard)"
  "200|http://admin.iam-68130677.com/edit/portal|admin-68130677 (edit portal)"
  "200|http://admin.iam-68130677.com/edit/research|admin-68130677 (edit research)"
  "404|http://www.iam-68130677.com/edit/portal|security isolation (www /edit blocked)"
)

ALL_PASSED=1
HTTP_LOG=""
for entry in "${CHECKS[@]}"; do
  IFS='|' read -r expected url label <<< "$entry"
  actual="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" || echo "ERR")"
  if [[ "$actual" == "$expected" ]]; then
    line="[PASS] HTTP ${actual} (expected ${expected})  ${url}  -- ${label}"
  else
    line="[FAIL] HTTP ${actual} (expected ${expected})  ${url}  -- ${label}"
    ALL_PASSED=0
  fi
  echo "$line"
  HTTP_LOG+="${line}"$'\n'
done

cat > "$LOG_FILE" <<EOF
=== Verification Timestamp: $(date '+%Y-%m-%d %H:%M:%S') ===

--- kubectl get nodes -o wide ---
${NODES_OUT}

--- kubectl get all,pvc,ingress -n ${NAMESPACE} -o wide ---
${GET_OUT}

--- HTTP Endpoint Verification ---
${HTTP_LOG}
--- kubectl describe ingress -n ${NAMESPACE} ---
${DESC_OUT}
EOF

echo ""
echo "Saved full verification output to: ${LOG_FILE}"

if [[ "$ALL_PASSED" -ne 1 ]]; then
  fail "One or more HTTP verification checks failed. Inspect ${LOG_FILE}."
fi

echo ""
echo "============================================================"
echo " 3-NODE K8S CLUSTER DEPLOYED AND VERIFIED SUCCESSFULLY!"
echo " Test URLs:"
echo "   http://www.iam-68130677.com"
echo "   http://www.id-68130677.com"
echo "   http://www.iam-68130677.com/research"
echo "   http://www.iam-68130677.com/api-68130677/Hello"
echo "   http://admin.iam-68130677.com"
echo "============================================================"
