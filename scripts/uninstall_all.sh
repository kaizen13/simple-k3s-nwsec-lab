#!/bin/bash

set -e  # Exit on error

echo "=========================================="
echo "K3s Network Security Lab - Full Uninstall"
echo "=========================================="
echo ""

# =============================================================================
# Safety Confirmation
# =============================================================================
echo "WARNING: This will completely remove:"
echo "  - Sample application and namespace"
echo "  - MetalLB load balancer"
echo "  - Traefik ingress controller"
echo "  - K3s Kubernetes distribution"
echo "  - TLS certificates"
echo "  - /etc/hosts entries"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted. No changes were made."
  exit 0
fi
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

# Keep sudo timestamp alive during long operations
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit 0; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap "kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

# Preserve user's HOME and original user info
ORIGINAL_USER="$SUDO_USER"
if [ -z "$ORIGINAL_USER" ]; then
  ORIGINAL_USER="$(whoami)"
fi
ORIGINAL_HOME="/home/$ORIGINAL_USER"

echo "  Running as user: $ORIGINAL_USER"
echo ""

# =============================================================================
# Get paths and setup
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Use kubectl wrapper for TLS verification if available
KUBECTL="/usr/local/bin/kubectl-wrapper"
if [ ! -x "$KUBECTL" ]; then
  KUBECTL="kubectl --insecure-skip-tls-verify"
fi

# =============================================================================
# Step 1: Remove sample app
# =============================================================================
echo "[1/6] Removing sample application..."
if $KUBECTL get namespace sample-app > /dev/null 2>&1; then
  $KUBECTL delete namespace sample-app --ignore-not-found || true
  echo "  Sample app namespace removed."
else
  echo "  Sample app namespace does not exist."
fi
echo ""

# =============================================================================
# Step 2: Remove MetalLB
# =============================================================================
echo "[2/6] Removing MetalLB..."
if [ -f "$PROJECT_DIR/backend/k8s/metallb-config.yaml" ]; then
  $KUBECTL delete -f "$PROJECT_DIR/backend/k8s/metallb-config.yaml" --ignore-not-found || true
fi
$KUBECTL delete -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml --ignore-not-found || true
echo "  MetalLB removed."
echo ""

# =============================================================================
# Step 3: Remove Traefik
# =============================================================================
echo "[3/6] Removing Traefik..."
if helm list -n kube-system 2>/dev/null | grep -q traefik; then
  helm uninstall traefik -n kube-system --kube-insecure-skip-tls-verify || true
  echo "  Traefik helm release removed."
else
  echo "  Traefik helm release not found."
fi
echo ""

# =============================================================================
# Step 4: Remove TLS certificates
# =============================================================================
echo "[4/6] Removing TLS certificates..."
if [ -f "$PROJECT_DIR/tls.crt" ]; then
  rm -f "$PROJECT_DIR/tls.crt"
  echo "  tls.crt removed."
fi
if [ -f "$PROJECT_DIR/tls.key" ]; then
  rm -f "$PROJECT_DIR/tls.key"
  echo "  tls.key removed."
fi
if [ -f "$PROJECT_DIR/sample-backend.tar" ]; then
  rm -f "$PROJECT_DIR/sample-backend.tar"
  echo "  sample-backend.tar removed."
fi
echo ""

# =============================================================================
# Step 5: Clean up /etc/hosts
# =============================================================================
echo "[5/6] Cleaning up /etc/hosts..."
if sudo grep -q "demo.jwst.lan" /etc/hosts; then
  sudo sed -i '/demo.jwst.lan/d' /etc/hosts
  echo "  Removed demo.jwst.lan from /etc/hosts"
else
  echo "  No demo.jwst.lan entry found in /etc/hosts"
fi
echo ""

# =============================================================================
# Step 6: Uninstall K3s
# =============================================================================
echo "[6/6] Uninstalling K3s..."
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
  sudo /usr/local/bin/k3s-uninstall.sh
  echo "  K3s uninstalled."
elif [ -f /usr/lib/systemd/system/k3s.service ]; then
  echo "  K3s uninstall script not found. Stopping services..."
  sudo systemctl stop k3s || true
  sudo systemctl disable k3s || true
  echo "  K3s service stopped and disabled."
  echo "  Manual cleanup may be required."
else
  echo "  K3s does not appear to be installed."
fi
echo ""

# =============================================================================
# Clean up user configuration
# =============================================================================
echo "Cleaning up user configuration..."

# Remove kubectl wrapper
if [ -f /usr/local/bin/kubectl-wrapper ]; then
  sudo rm -f /usr/local/bin/kubectl-wrapper
  echo "  kubectl-wrapper removed."
fi

# Remove KUBECONFIG from bashrc
if [ -f "$ORIGINAL_HOME/.bashrc" ]; then
  sudo sed -i '/export KUBECONFIG/d' "$ORIGINAL_HOME/.bashrc" 2>/dev/null || true
  sudo sed -i '/alias kubectl="kubectl-wrapper"/d' "$ORIGINAL_HOME/.bashrc" 2>/dev/null || true
  echo "  bashrc cleaned."
fi

# Remove .kube directory
if [ -d "$ORIGINAL_HOME/.kube" ]; then
  rm -rf "$ORIGINAL_HOME/.kube"
  echo "  .kube directory removed."
fi
echo ""

echo "=========================================="
echo "Full Uninstall Complete!"
echo "=========================================="
echo ""
echo "All K3s lab components have been removed."
echo ""
echo "To reinstall from scratch:"
echo "  1. ./scripts/install_k3s.sh"
echo "  2. ./scripts/deploy_sample_app.sh"
echo ""
echo "Access the application at:"
echo "  https://demo.jwst.lan"
echo "=========================================="
