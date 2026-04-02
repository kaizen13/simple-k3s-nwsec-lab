#!/bin/bash

# Get the script directory for absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Use kubectl wrapper for TLS verification
KUBECTL=/usr/local/bin/kubectl-wrapper

# Remove the sample app resources
echo "Removing sample app resources..."
$KUBECTL delete namespace sample-app

# Remove MetalLB configuration
echo "Removing MetalLB configuration..."
$KUBECTL delete -f "$PROJECT_DIR/backend/k8s/metallb-config.yaml" || true

# Uninstall MetalLB
echo "Uninstalling MetalLB..."
$KUBECTL delete -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml

# Uninstall Traefik
echo "Uninstalling Traefik..."
helm uninstall traefik -n kube-system --kube-insecure-skip-tls-verify

# Remove TLS certificates
echo "Removing TLS certificates..."
rm -f tls.crt tls.key

# Remove the entry from /etc/hosts
echo "Removing entry from /etc/hosts..."
sudo sed -i '/demo.jwst.lan/d' /etc/hosts

# Uninstall K3s
echo "Uninstalling K3s..."
sudo /usr/local/bin/k3s-uninstall.sh

echo "All components have been removed successfully."