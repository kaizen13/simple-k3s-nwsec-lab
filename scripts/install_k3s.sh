#!/bin/bash

set -e  # Exit on error

echo "=========================================="
echo "K3s Network Security Lab - Installation"
echo "=========================================="

# Install K3s
echo "[1/7] Installing K3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san=k3s-node1 --disable traefik" sh -

# Enable and start buildkit service
echo "[2/7] Enabling buildkit service..."
sudo systemctl enable --now buildkit

# Wait for K3s to be ready
echo "[3/7] Waiting for K3s to be ready..."
while ! sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl --insecure-skip-tls-verify get nodes; do
  echo "  Waiting for K3s nodes..."
  sleep 5
done

# Set up kubectl for the current user
echo "[4/7] Setting up kubectl..."
sudo mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown -R "$(id -u):$(id -g)" "$HOME/.kube"
echo 'export KUBECONFIG=$HOME/.kube/config' >> "$HOME/.bashrc" || true

# Create kubectl wrapper for TLS verification
echo "  Creating kubectl wrapper..."
echo '#!/bin/bash' | sudo tee /usr/local/bin/kubectl-wrapper > /dev/null
echo 'exec kubectl --insecure-skip-tls-verify "$@"' | sudo tee -a /usr/local/bin/kubectl-wrapper > /dev/null
sudo chmod +x /usr/local/bin/kubectl-wrapper
echo 'alias kubectl="kubectl-wrapper"' >> "$HOME/.bashrc" || true

KUBECTL=/usr/local/bin/kubectl-wrapper

# Get paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Install MetalLB
echo "[5/7] Installing MetalLB..."

# Create metallb-system namespace with pod security labels
$KUBECTL apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
EOF

# Install MetalLB manifests
echo "  Applying MetalLB manifests..."
$KUBECTL apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# Wait for MetalLB controller to be ready
echo "  Waiting for MetalLB controller..."
$KUBECTL wait --for=condition=available deployment/controller -n metallb-system --timeout=120s || {
  echo "  Warning: MetalLB controller not ready yet, continuing..."
}

# Apply MetalLB configuration
echo "  Applying MetalLB configuration..."
$KUBECTL apply -f "$PROJECT_DIR/backend/k8s/metallb-config.yaml"

# Verify MetalLB resources
echo "  Verifying MetalLB resources..."
sleep 5
$KUBECTL get ipaddresspool -n metallb-system || echo "  Warning: IPAddressPool not found"
$KUBECTL get l2advertisement -n metallb-system || echo "  Warning: L2Advertisement not found"

# Install Traefik
echo "[6/7] Installing Traefik..."

# Add Helm repo
helm repo add traefik https://traefik.github.io/charts 2>/dev/null || helm repo update
helm repo update

# Install Traefik with proper configuration
echo "  Installing Traefik via Helm..."
helm install traefik traefik/traefik \
  -n kube-system \
  --kube-insecure-skip-tls-verify \
  --set ports.websecure.http.tls.enabled=true \
  --set ports.websecure.http.tls.certResolver="" \
  --wait --timeout=5m

# Wait for Traefik to be ready
echo "  Waiting for Traefik to be ready..."
$KUBECTL wait --for=condition=available deployment/traefik -n kube-system --timeout=120s || {
  echo "  Warning: Traefik not fully ready yet, continuing..."
}

# Wait for Traefik External IP
echo "  Waiting for Traefik External IP..."
TIMEOUT=120
ELAPSED=0
EXTERNAL_IP=""
while [ $ELAPSED -lt $TIMEOUT ]; do
  EXTERNAL_IP=$($KUBECTL get service traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if echo "$EXTERNAL_IP" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' > /dev/null; then
    echo "  External IP acquired: $EXTERNAL_IP"
    break
  fi
  echo "  Waiting for External IP... ($ELAPSED/$TIMEOUT seconds)"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ -z "$EXTERNAL_IP" ]; then
  echo "  Warning: Could not get External IP, using default 172.20.20.20"
  EXTERNAL_IP="172.20.20.20"
fi

# Update /etc/hosts
echo "[7/7] Updating /etc/hosts..."
if ! grep -q "demo.jwst.lan" /etc/hosts; then
  echo "$EXTERNAL_IP demo.jwst.lan" | sudo tee -a /etc/hosts
  echo "  Added entry: $EXTERNAL_IP demo.jwst.lan"
else
  echo "  Entry already exists in /etc/hosts"
fi

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Deploy the sample application:"
echo "     sudo bash scripts/deploy_sample_app.sh"
echo ""
echo "  2. Access the application at:"
echo "     https://demo.jwst.lan"
echo ""
echo "  Traefik External IP: $EXTERNAL_IP"
echo "=========================================="
