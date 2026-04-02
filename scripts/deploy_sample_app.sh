#!/bin/bash

# Get the script directory for absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Use kubectl wrapper for TLS verification
KUBECTL=/usr/local/bin/kubectl-wrapper

# Create a namespace for the sample app
$KUBECTL create namespace sample-app

# Clean up nerdctl cache to prevent build issues
echo "Cleaning up nerdctl cache..."
sudo nerdctl system prune -a -f

# Build the backend image with nerdctl
echo "Building the backend image..."
sudo nerdctl --namespace=k8s.io build -t sample-backend:v1 backend/

# Save the image to a tar file
echo "Saving the image to a tar file..."
sudo nerdctl --namespace=k8s.io save sample-backend:v1 -o sample-backend.tar

# Import the image into K3s
echo "Importing the image into K3s..."
sudo k3s ctr images import "$PROJECT_DIR/sample-backend.tar"

# Deploy Redis (Database Tier)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: sample-app
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
spec:
  selector:
    app: redis
  ports:
    - protocol: TCP
      port: 6379
      targetPort: 6379
EOF

# Deploy Node.js Backend (Backend Tier)
$KUBECTL apply -f "$PROJECT_DIR/backend/k8s/backend-deployment.yaml"

# Deploy Nginx Frontend (Frontend Tier)
$KUBECTL apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: sample-app
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
spec:
  selector:
    app: frontend
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
EOF

# Create TLS certificates
echo "Creating TLS certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=demo.jwst.lan" -addext "subjectAltName=DNS:demo.jwst.lan"

# Create Kubernetes secret for TLS
echo "Creating Kubernetes secret for TLS..."
$KUBECTL create secret tls demo-lab-local-tls --cert="$PROJECT_DIR/tls.crt" --key="$PROJECT_DIR/tls.key" -n sample-app

# Update /etc/hosts
echo "Updating /etc/hosts..."
echo "172.20.20.20 demo.jwst.lan" | sudo tee -a /etc/hosts

# Create Ingress for the sample app
$KUBECTL apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app-ingress
  namespace: sample-app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
spec:
  tls:
  - hosts:
    - demo.jwst.lan
    secretName: demo-lab-local-tls
  rules:
  - host: demo.jwst.lan
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
EOF