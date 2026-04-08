#!/bin/bash

set -e  # Exit on error

echo "=========================================="
echo "K3s Network Security Lab - Deploy App"
echo "=========================================="
echo ""

# =============================================================================
# Privilege Check - Request sudo once at the start
# =============================================================================
echo "Checking privileges..."
if ! sudo -v 2>/dev/null; then
  echo "Error: This script requires sudo privileges for container operations."
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

# Use kubectl wrapper for TLS verification
KUBECTL=/usr/local/bin/kubectl-wrapper

# Verify kubectl wrapper exists
if [ ! -x "$KUBECTL" ]; then
  echo "Error: kubectl wrapper not found at $KUBECTL"
  echo "Please run ./scripts/install_k3s.sh first."
  exit 1
fi

# Verify K3s is running
if ! $KUBECTL cluster-info > /dev/null 2>&1; then
  echo "Error: Cannot connect to K3s cluster."
  echo "Please ensure K3s is installed and running."
  exit 1
fi

echo "K3s cluster connection verified."
echo ""

# =============================================================================
# Create namespace
# =============================================================================
echo "[1/6] Creating namespace..."
$KUBECTL create namespace sample-app --dry-run=client -o yaml | $KUBECTL apply -f -
echo "  Namespace 'sample-app' created/verified."
echo ""

# =============================================================================
# Clean up nerdctl cache
# =============================================================================
# Define the sockets (Ensure these match where they actually live on your disk)
K3S_SOCK="/run/k3s/containerd/containerd.sock"
BK_SOCK="unix:///run/buildkit/buildkitd.sock"

# [2/6] Cleaning up nerdctl cache
echo "[2/6] Cleaning up nerdctl cache..."
sudo nerdctl --address "$K3S_SOCK" --buildkit-host "$BK_SOCK" system prune -a -f

# [3/6] Building backend image
echo "[3/6] Building backend image..."
cd "$PROJECT_DIR/backend"
sudo -E nerdctl --address "$K3S_SOCK" --namespace=k8s.io --buildkit-host "$BK_SOCK" build -t sample-backend:v1 .
echo "  Backend image built: sample-backend:v1"
echo ""

# =============================================================================
# Save and import image
# =============================================================================
#echo "[4/6] Saving and importing image..."
#sudo nerdctl --namespace=k8s.io save sample-backend:v1 -o "$PROJECT_DIR/sample-backend.tar"
#sudo k3s ctr images import "$PROJECT_DIR/sample-backend.tar"
#echo "  Image imported into K3s."
#echo ""
echo "  Image is now available in the k8s.io namespace."

# =============================================================================
# Deploy Redis
# =============================================================================
echo "[5/6] Deploying Redis..."
$KUBECTL apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: sample-app
  labels:
    app: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:alpine
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: sample-app
  labels:
    app: redis
spec:
  selector:
    app: redis
  ports:
    - protocol: TCP
      port: 6379
      targetPort: 6379
EOF
echo "  Redis deployed."
echo ""

# =============================================================================
# Deploy Backend
# =============================================================================
echo "[6/6] Deploying Backend..."
$KUBECTL apply -f "$PROJECT_DIR/backend/k8s/backend-deployment.yaml"
echo "  Backend deployed."
echo ""

# =============================================================================
# Deploy Frontend
# =============================================================================
echo "Deploying Frontend..."
$KUBECTL apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: sample-app
  labels:
    app: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: default.conf
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: sample-app
data:
  default.conf: |
    server {
      listen 80;
      server_name localhost;

      location / {
        proxy_pass http://backend.sample-app.svc.cluster.local:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
      }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: sample-app
  labels:
    app: frontend
spec:
  selector:
    app: frontend
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
EOF
echo "  Frontend deployed."
echo ""

# =============================================================================
# Create TLS certificates
# =============================================================================
echo "Creating TLS certificates..."
cd "$PROJECT_DIR"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=demo.jwst.lan" \
  -addext "subjectAltName=DNS:demo.jwst.lan" 2>/dev/null

# Set proper ownership for generated certificates
sudo chown "$ORIGINAL_USER:$ORIGINAL_USER" tls.crt tls.key
sudo chmod 644 tls.crt
sudo chmod 600 tls.key

echo "  TLS certificates generated."
echo ""

# =============================================================================
# Create Kubernetes secret for TLS
# =============================================================================
echo "Creating TLS secret..."
$KUBECTL delete secret demo-lab-local-tls -n sample-app --ignore-not-found
$KUBECTL create secret tls demo-lab-local-tls \
  --cert="$PROJECT_DIR/tls.crt" \
  --key="$PROJECT_DIR/tls.key" \
  -n sample-app
echo "  TLS secret created."
echo ""

# =============================================================================
# Update /etc/hosts
# =============================================================================
echo "Updating /etc/hosts..."
if ! grep -q "demo.jwst.lan" /etc/hosts; then
  echo "172.20.20.20 demo.jwst.lan" | sudo tee -a /etc/hosts > /dev/null
  echo "  Added entry to /etc/hosts"
else
  echo "  Entry already exists in /etc/hosts"
fi
echo ""

# =============================================================================
# Deploy IngressRoute and Middleware
# =============================================================================
echo "Deploying IngressRoute and Middleware..."
$KUBECTL apply -f "$PROJECT_DIR/backend/k8s/ingress-updated.yaml"
echo "  IngressRoute and Middleware deployed."
echo ""

# =============================================================================
# Wait for pods to be ready
# =============================================================================
echo "Waiting for pods to be ready..."
$KUBECTL wait --for=condition=ready pod -l app=redis -n sample-app --timeout=60s || true
$KUBECTL wait --for=condition=ready pod -l app=backend -n sample-app --timeout=60s || true
$KUBECTL wait --for=condition=ready pod -l app=frontend -n sample-app --timeout=60s || true

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Access the application at:"
echo "  https://demo.jwst.lan"
echo ""
echo "Note: Your browser will show a security warning"
echo "      due to the self-signed certificate."
echo "=========================================="
