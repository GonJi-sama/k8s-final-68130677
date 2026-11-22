#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECTL_BIN="$(command -v kubectl 2>/dev/null || echo "${SCRIPT_DIR}/bin/kubectl")"

echo "============================================================"
echo " Kubernetes 3-Node Verification Report - ID 68130677"
echo "============================================================"

echo ""
echo "--- [1] Cluster Nodes (Must be 3 Ready Nodes) ---"
"$KUBECTL_BIN" --context kind-k8s-68130677 get nodes -o wide

echo ""
echo "--- [2] Resources in namespace iam-68130677 ---"
"$KUBECTL_BIN" --context kind-k8s-68130677 get all,pvc,ingress -n iam-68130677 -o wide

echo ""
echo "--- [3] Describe Ingress ---"
"$KUBECTL_BIN" --context kind-k8s-68130677 describe ingress ingress-public ingress-admin -n iam-68130677

echo ""
echo "--- [4] HTTP Status Checks ---"
for u in   "http://www.iam-68130677.com/"   "http://www.id-68130677.com/"   "http://www.iam-68130677.com/research"   "http://www.iam-68130677.com/api-68130677/Hello"   "http://admin.iam-68130677.com/"   "http://admin.iam-68130677.com/edit/portal"   "http://admin.iam-68130677.com/edit/research"   "http://www.iam-68130677.com/edit/portal"; do
  curl -s -o /dev/null -w "HTTP %{http_code}  %{url_effective}\n" "$u"
done
echo "(Note: http://www.iam-68130677.com/edit/portal MUST return HTTP 404)"
