#!/bin/bash

set -e  # Exit on error

echo "=========================================="
echo "K3s Network Security Lab - Remove App"
echo "=========================================="
echo ""

# =============================================================================
# Privilege Check - Request sudo once at the start
# =============================================================================
echo "Checking privileges..."
if ! sudo -v 2>/dev/null; then
  echo "Error: This script requires sudo privileges."
  echo "Please ensure your user has sudo access and try again."
  exit 1
fi
echo "  Sudo privileges verified."
echo ""

# =============================================================================
# Get paths and setup
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Use kubectl wrapper for TLS verification
KUBECTL=/usr/local/bin/kubectl-wrapper

# Verify kubectl wrapper exists
if [ ! -x "$KUBECTL" ]; then
  echo "Warning: kubectl wrapper not found at $KUBECTL"
  echo "Attempting to use kubectl directly..."
  KUBECTL="kubectl --insecure-skip-tls-verify"
fi

# =============================================================================
# Remove sample app namespace
# =============================================================================
echo "[1/4] Removing sample app namespace..."
if $KUBECTL get namespace sample-app > /dev/null 2>&1; then
  $KUBECTL delete namespace sample-app
  echo "  Namespace 'sample-app' deleted."
else
  echo "  Namespace 'sample-app' does not exist."
fi
echo ""

# =============================================================================
# Remove MetalLB configuration
# =============================================================================
echo "[2/4] Removing MetalLB configuration..."
if [ -f "$PROJECT_DIR/backend/k8s/metallb-config.yaml" ]; then
  $KUBECTL delete -f "$PROJECT_DIR/backend/k8s/metallb-config.yaml" --ignore-not-found || true
  echo "  MetalLB configuration removed."
else
  echo "  MetalLB configuration file not found."
fi
echo ""

# =============================================================================
# Uninstall MetalLB
# =============================================================================
echo "[3/4] Uninstalling MetalLB..."
$KUBECTL delete -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml --ignore-not-found || true
echo "  MetalLB uninstalled."
echo ""

# =============================================================================
# Uninstall Traefik
# =============================================================================
echo "[4/4] Uninstalling Traefik..."
if helm list -n kube-system 2>/dev/null | grep -q traefik; then
  helm uninstall traefik -n kube-system --kube-insecure-skip-tls-verify
  echo "  Traefik uninstalled."
else
  echo "  Traefik helm release not found."
fi
echo ""

# =============================================================================
# Remove /etc/hosts entry
# =============================================================================
echo "Cleaning up /etc/hosts..."
if sudo grep -q "demo.jwst.lan" /etc/hosts; then
  sudo sed -i '/demo.jwst.lan/d' /etc/hosts
  echo "  Removed demo.jwst.lan from /etc/hosts"
else
  echo "  No demo.jwst.lan entry found in /etc/hosts"
fi
echo ""

echo "=========================================="
echo "Sample App Removal Complete!"
echo "=========================================="
echo ""
echo "The K3s cluster is still running."
echo "To reinstall the app: ./scripts/deploy_sample_app.sh"
echo "To uninstall everything: ./scripts/uninstall_all.sh"
echo "=========================================="
