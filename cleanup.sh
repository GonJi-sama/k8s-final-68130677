#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_BIN="$(command -v kind 2>/dev/null || echo "${SCRIPT_DIR}/bin/kind")"

echo "Deleting Kind 3-node cluster k8s-68130677..."
"$KIND_BIN" delete cluster --name k8s-68130677
echo "Done."
echo "Optional: to remove domain entries from /etc/hosts, run:"
echo "  sudo sed -i '/68130677\.com/d' /etc/hosts"
