#!/bin/bash

# Get the script directory for absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Use kubectl wrapper for TLS verification
KUBECTL=/usr/local/bin/kubectl-wrapper

# Remove the sample app resources
$KUBECTL delete namespace sample-app

# Remove MetalLB configuration
$KUBECTL delete -f "$PROJECT_DIR/backend/k8s/metallb-config.yaml" || true

# Uninstall MetalLB
$KUBECTL delete -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml

# Uninstall Traefik
helm uninstall traefik -n kube-system

# Remove the entry from /etc/hosts
sudo sed -i '/sample-app.local/d' /etc/hosts