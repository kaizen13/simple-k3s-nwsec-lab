# K3s Network Security Lab - Project Context

## Project Overview

This is a **Kubernetes networking and security lab** built on K3s (lightweight Kubernetes). It deploys a 3-tier web application (frontend, backend, Redis) with Traefik ingress controller and MetalLB load balancer for practicing network security, ingress configurations, and TLS setups.

### Architecture Diagram

```
                                    ┌─────────────────┐
                                    │  demo.jwst.lan  │
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │    MetalLB      │
                                    │  172.20.20.20   │
                                    │  (L2 Mode)      │
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │    Traefik      │
                                    │  (Ingress +     │
                                    │   TLS Term.)    │
                                    │  :80 → :443     │
                                    └────────┬────────┘
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    │                    sample-app                   │
                    │                                                 │
                    │  ┌──────────┐    ┌──────────┐    ┌──────────┐  │
                    │  │ Frontend │───▶│ Backend  │───▶│  Redis   │  │
                    │  │  (Nginx) │    │ (Node.js) │    │  (Cache) │  │
                    │  │  :80     │    │  :3000   │    │  :6379   │  │
                    │  └──────────┘    └──────────┘    └──────────┘  │
                    └─────────────────────────────────────────────────┘
```

### Key Components

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **K3s** | Lightweight Kubernetes | Latest | Container orchestration |
| **MetalLB** | Load Balancer | v0.13.12+ | Provides external IPs for bare-metal K8s |
| **Traefik** | Ingress Controller | v3.x | Routes external traffic, TLS termination, HTTP→HTTPS redirect |
| **Frontend** | Nginx (alpine) | Latest | Reverse proxy to backend |
| **Backend** | Node.js 18 + Express | 18.x | Serves application logic |
| **Redis** | Redis Alpine | Latest | In-memory data store |

## Directory Structure

```
/home/k3s/k3s-nwsec-lab2/
├── backend/
│   ├── k8s/
│   │   ├── backend-deployment.yaml    # Backend deployment + service + ConfigMap
│   │   ├── ingress-updated.yaml       # Ingress + Middleware (HTTP→HTTPS redirect)
│   │   ├── metallb-config.yaml        # MetalLB IP pool and L2 advertisement
│   │   └── middleware-redirect.yaml   # Standalone Middleware resource
│   ├── Dockerfile                     # Backend container build instructions
│   ├── package.json                   # Node.js dependencies (express, redis)
│   └── script.js                      # Express application code
├── frontend/                          # Empty - uses Nginx directly via deploy script
├── scripts/
│   ├── deploy_sample_app.sh           # Deploys sample app and all resources
│   ├── install_k3s.sh                 # Installs K3s, MetalLB, Traefik (with PSA labels)
│   ├── remove_sample_app.sh           # Removes sample app resources
│   └── uninstall_all.sh               # Complete cleanup
├── tls.crt                            # Self-signed TLS certificate (auto-generated)
├── tls.key                            # Self-signed TLS private key (auto-generated)
├── sample-backend.tar                 # Pre-built backend image (nerdctl)
├── .gitignore                         # Git ignore rules (security)
├── LICENSE                            # MIT License
├── README.md                          # User documentation
└── QWEN.md                            # This context file
```

## Building and Running

### Initial Setup (Fresh Environment)

```bash
# Step 1: Install K3s, MetalLB, and Traefik
sudo bash scripts/install_k3s.sh

# Step 2: Deploy the sample application
sudo bash scripts/deploy_sample_app.sh
```

### Accessing the Application

| Protocol | URL | Behavior |
|----------|-----|----------|
| HTTPS | `https://demo.jwst.lan` | Direct access (200 OK) |
| HTTP | `http://demo.jwst.lan` | 308 Redirect to HTTPS |

**Note:** Browser will show SSL warning (self-signed certificate) - this is expected.

### Key Commands

```bash
# Check pod status
kubectl get pods -n sample-app

# Check ingress status
kubectl get ingress -n sample-app

# Check Traefik service (external IP)
kubectl get service traefik -n kube-system

# Check MetalLB configuration
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Check Middleware resources
kubectl get middleware -n sample-app

# Apply individual manifests
kubectl apply -f backend/k8s/<file>.yaml

# Delete namespace (cleanup)
kubectl delete namespace sample-app
```

### kubectl Wrapper

Due to self-signed certificates, use the wrapper script:
```bash
/usr/local/bin/kubectl-wrapper   # Adds --insecure-skip-tls-verify flag
```

## Development Conventions

### Kubernetes Resources

- All resources use the `sample-app` namespace
- Labels follow pattern: `app.kubernetes.io/name: sample-app`, `app.kubernetes.io/component: <component>`
- Services use ClusterIP (default) for internal communication

### Ingress Configuration

The ingress uses Traefik-specific annotations for HTTP→HTTPS redirect:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app-ingress
  namespace: sample-app
  labels:
    app.kubernetes.io/name: sample-app
    app.kubernetes.io/component: ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
    traefik.ingress.kubernetes.io/router.middlewares: sample-app-redirect-https@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
  - host: demo.jwst.lan
    http:
      paths:
      - backend:
          service:
            name: frontend
            port:
              number: 80
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - demo.jwst.lan
    secretName: demo-lab-local-tls
```

**Important:** The middleware name in the annotation must match the Middleware resource name exactly:
- Annotation reference: `sample-app-redirect-https@kubernetescrd`
- Middleware name: `sample-app-redirect-https`
- Middleware namespace: `sample-app`

### Middleware Configuration

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: sample-app-redirect-https
  namespace: sample-app
  labels:
    app.kubernetes.io/name: sample-app
    app.kubernetes.io/component: middleware
spec:
  redirectScheme:
    scheme: https
    permanent: true
    port: "443"
```

### TLS Setup

- Self-signed certificates generated via OpenSSL
- Stored as Kubernetes Secret: `demo-lab-local-tls`
- Certificate CN and SAN: `demo.jwst.lan`
- Validity: 365 days
- Key: RSA 2048-bit

### MetalLB Configuration

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ingress-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.20.20.20-172.20.20.40
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - ingress-pool
  nodeSelectors:
  - matchExpressions:
    - key: kubernetes.io/os
      operator: In
      values:
      - linux
```

### Pod Security Admission

MetalLB requires privileged mode. The install script creates the namespace with proper labels:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

## Testing & Verification

### Test HTTP→HTTPS Redirect

```bash
# Should return 308 Permanent Redirect
curl -I http://demo.jwst.lan
# Expected:
#   HTTP/1.1 308 Permanent Redirect
#   Location: https://demo.jwst.lan/

# Should return 200 OK
curl -kI https://demo.jwst.lan
# Expected:
#   HTTP/2 200
```

### Verify Components

```bash
# All pods should be Running
kubectl get pods -n sample-app

# Ingress should show 80, 443 ports
kubectl get ingress -n sample-app

# Middleware should exist
kubectl get middleware -n sample-app

# MetalLB should have IP pool configured
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| HTTP redirect not working | Middleware name mismatch | Verify annotation matches middleware name |
| 404 on both HTTP/HTTPS | Ingress not applied | Reapply `ingress-updated.yaml` |
| Default TLS cert shown | Secret not found | Verify `demo-lab-local-tls` exists |
| External IP pending | MetalLB misconfigured | Check IPAddressPool range, namespace labels |
| Backend not responding | Image not imported | Run `sudo k3s ctr images import sample-backend.tar` |
| MetalLB speaker failing | Missing PSA labels | Add privileged labels to metallb-system namespace |

### Debug Commands

```bash
# Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50

# Describe ingress for events
kubectl describe ingress sample-app-ingress -n sample-app

# Check TLS secret
kubectl get secret demo-lab-local-tls -n sample-app -o yaml

# Check MetalLB speaker logs
kubectl logs -n metallb-system -l component=speaker --tail=50

# Check MetalLB controller logs
kubectl logs -n metallb-system -l component=controller --tail=50
```

## Testing Network Policies

This lab is designed for network security testing:

```bash
# Example: Restrict backend access to frontend only
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: sample-app
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 3000
EOF
```

## Security Considerations

⚠️ **This is a lab environment - not for production use!**

- Self-signed certificates (not trusted by browsers)
- No rate limiting configured
- Default Traefik dashboard may be exposed
- Network policies are permissive by default
- MetalLB runs in privileged mode (required for L2 advertisement)
- Consider adding ResourceQuotas for production-like testing

## Related Files

| File | Purpose |
|------|---------|
| `backend/k8s/ingress-updated.yaml` | Ingress + Middleware (recommended, all-in-one) |
| `backend/k8s/middleware-redirect.yaml` | Standalone Middleware |
| `backend/k8s/backend-deployment.yaml` | Backend deployment with ConfigMap |
| `backend/k8s/metallb-config.yaml` | MetalLB IP pool with L2 advertisement |
| `scripts/install_k3s.sh` | Full K3s + MetalLB + Traefik install (with PSA) |
| `scripts/deploy_sample_app.sh` | Application deployment |
| `scripts/remove_sample_app.sh` | Remove application only |
| `scripts/uninstall_all.sh` | Complete cleanup |

## Version Information

| Component | Version | Notes |
|-----------|---------|-------|
| K3s | Latest | Installed via curl script |
| MetalLB | v0.13.12 | Native manifests |
| Traefik | v3.x | Helm chart |
| Node.js | 18-alpine | Backend base image |
| Redis | alpine | Database |
| Nginx | alpine | Frontend |
