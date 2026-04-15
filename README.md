# K3s Network Security Lab

A **lightweight Kubernetes networking lab** built on K3s with a 3-tier web application, featuring HTTP→HTTPS redirect, TLS termination, and network security policy testing capabilities.

## Overview

This lab provides a complete environment for learning and testing Kubernetes networking concepts:

- **K3s** - Lightweight Kubernetes distribution
- **MetalLB** - Load balancer for bare-metal deployments
- **Traefik** - Ingress controller with HTTP→HTTPS redirect
- **3-Tier Application** - Frontend (Nginx), Backend (Node.js), Database (Redis)

## Features

- ✅ Automatic HTTP to HTTPS redirection via Traefik Middleware (308 Permanent Redirect)
- ✅ TLS termination with self-signed certificates
- ✅ MetalLB load balancer with L2 advertisement
- ✅ Network policy testing capabilities
- ✅ Easy deployment and cleanup scripts
- ✅ Pod Security Admission compliant

## Quick Start

### Prerequisites

- Ubuntu/Debian Linux machine (22.04+ recommended)
- Root or sudo access
- Internet connection (for downloading K3s, MetalLB, Traefik)
- Helm 3.x installed

### Installation

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Step 1: Install prerequisites, K3s, MetalLB, and Traefik
./scripts/install_k3s.sh

# Step 2: Deploy the sample application
./scripts/deploy_sample_app.sh
```

> **Note:** The `install_k3s.sh` script automatically installs all required prerequisites (runc, CNI plugins, rootlesskit, etc.) by calling `install_prerequisites.sh`. The scripts will request sudo privileges when needed for system-level operations (installing K3s, modifying /etc/hosts, container operations). User-level configuration is handled automatically.

### Access the Application

The application will be available at:
- **HTTPS:** `https://<your-configured-fqdn>`
- **HTTP:** `http://<your-configured-fqdn>` (automatically redirects to HTTPS)

> **Note:** During installation, you will be prompted to enter a custom FQDN for the lab. The default value is `demo.testlab.lan`. Your browser will show a security warning due to the self-signed certificate. This is expected behavior for a lab environment.

## Architecture

```
                                    ┌─────────────────┐
                                    │   <your-fqdn>   │
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
                    │  │  (Nginx) │    │ (Node.js)│    │  (Cache) │  │
                    │  │  :80     │    │  :3000   │    │  :6379   │  │
                    │  └──────────┘    └──────────┘    └──────────┘  │
                    └─────────────────────────────────────────────────┘
```

## Directory Structure

```
.
├── backend/
│   ├── k8s/
│   │   ├── backend-deployment.yaml    # Backend deployment, service, ConfigMap
│   │   ├── ingress-updated.yaml       # Ingress + Middleware (HTTP→HTTPS redirect)
│   │   ├── metallb-config.yaml        # MetalLB IP pool configuration
│   │   └── middleware-redirect.yaml   # Standalone redirect Middleware
│   ├── Dockerfile                     # Backend container image
│   ├── package.json                   # Node.js dependencies
│   └── script.js                      # Express application
├── frontend/                          # Uses Nginx (configured in deploy script)
├── scripts/
│   ├── install_prerequisites.sh       # Install runc, CNI plugins, etc.
│   ├── install_k3s.sh                 # Install K3s, MetalLB, Traefik
│   ├── deploy_sample_app.sh           # Deploy the 3-tier application
│   ├── remove_sample_app.sh           # Remove application resources
│   └── uninstall_all.sh               # Complete cleanup
├── .lab-config                        # Lab FQDN config (auto-generated)
├── tls.crt                            # Self-signed certificate (auto-generated)
├── tls.key                            # Certificate private key (auto-generated)
├── sample-backend.tar                 # Pre-built backend image
├── .gitignore                         # Git ignore rules
├── LICENSE                            # MIT License
├── README.md                          # This file
└── QWEN.md                            # Project context documentation
```

## Configuration Details

### Lab FQDN

During the first run of `install_prerequisites.sh`, you will be prompted to enter a Fully Qualified Domain Name (FQDN) for the lab. This FQDN is used for:

- TLS certificate generation (CN and SAN)
- `/etc/hosts` entries
- Traefik IngressRoute host matching
- All service URLs

The configuration is saved to `.lab-config` at the project root. If you want to change the FQDN after installation, you can either:
1. Edit `.lab-config` manually and re-run `deploy_sample_app.sh`
2. Run `install_prerequisites.sh` again to reconfigure

**Default value:** `demo.testlab.lan`

### MetalLB Configuration

MetalLB is configured with the following settings:

| Setting | Value |
|---------|-------|
| IP Range | `172.20.20.20-172.20.20.40` |
| Mode | Layer 2 (L2Advertisement) |
| Namespace | `metallb-system` |
| Pod Security | Privileged mode enabled |

### HTTP→HTTPS Redirect

The redirect is implemented using a Traefik Middleware and IngressRoute CRDs:

```yaml
apiVersion: traefik.io/v1alpha1  # Use traefik.io for Traefik v3.x
kind: Middleware
metadata:
  name: sample-app-redirect-https
  namespace: sample-app
spec:
  redirectScheme:
    scheme: https
    permanent: true
    port: "443"
```

Referenced in IngressRoute:
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: sample-app-http
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`demo.jwst.lan`)
      kind: Rule
      services:
        - name: frontend
          port: 80
      middlewares:
        - name: sample-app-redirect-https
```

> **Note:** Traefik v3.x works best with IngressRoute CRDs instead of standard Kubernetes Ingress resources. Standard Ingress has issues with middleware discovery in Traefik v3.x.

### TLS Configuration

| Setting | Value |
|---------|-------|
| Certificate CN | `<your-fqdn>` (default: `demo.testlab.lan`) |
| Subject Alternative Name | `DNS:<your-fqdn>` |
| Validity | 365 days |
| Kubernetes Secret | `demo-lab-local-tls` (in `sample-app` namespace) |
| Key Size | RSA 2048-bit |

### Traefik Configuration

| Setting | Value |
|---------|-------|
| Version | 3.x (via Helm) |
| Entrypoints | web (:8000), websecure (:8443) |
| TLS | Enabled on websecure |
| Dashboard | Enabled |
| Metrics | Prometheus endpoint |

## Usage Guide

### Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n sample-app

# Check ingress configuration
kubectl get ingress -n sample-app

# Check Traefik external IP
kubectl get service traefik -n kube-system

# Check MetalLB configuration
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Check Middleware resources
kubectl get middleware -n sample-app
```

### Test the Application

```bash
# Test HTTP redirect (should return 308)
curl -I http://<your-fqdn>
# Expected: HTTP/1.1 308 Permanent Redirect
#           Location: https://<your-fqdn>/

# Test HTTPS (should return 200)
curl -kI https://<your-fqdn>
# Expected: HTTP/2 200

# Test full page load
curl -k https://<your-fqdn>
```

### Apply Network Policies

This lab is ideal for testing Kubernetes NetworkPolicies:

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

## Cleanup

```bash
# Remove the sample application only
./scripts/remove_sample_app.sh

# Complete uninstall (K3s, MetalLB, Traefik, all resources)
./scripts/uninstall_all.sh
```

## Troubleshooting

### HTTP Redirect Not Working

1. Verify the Middleware exists:
   ```bash
   kubectl get middleware -n sample-app
   ```

2. Check Traefik logs:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50
   ```

3. Verify ingress annotations:
   ```bash
   kubectl describe ingress sample-app-ingress -n sample-app
   ```

### Application Not Accessible

1. Verify pods are running:
   ```bash
   kubectl get pods -n sample-app
   ```

2. Check if MetalLB has assigned an IP:
   ```bash
   kubectl get service traefik -n kube-system
   ```

3. Verify /etc/hosts entry:
   ```bash
   grep <your-fqdn> /etc/hosts
   ```

### MetalLB Installation Fails

1. Check if the namespace has proper labels:
   ```bash
   kubectl get namespace metallb-system -o yaml
   ```

2. Verify pod security admission:
   ```bash
   kubectl get pods -n metallb-system
   ```

3. Check speaker pod logs:
   ```bash
   kubectl logs -n metallb-system -l component=speaker
   ```

### Certificate Issues

Regenerate certificates:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=<your-fqdn>" \
  -addext "subjectAltName=DNS:<your-fqdn>"
```

Then update the secret:
```bash
kubectl delete secret demo-lab-local-tls -n sample-app
kubectl create secret tls demo-lab-local-tls \
  --cert=tls.crt --key=tls.key -n sample-app
```

## Security Notes

⚠️ **This is a lab environment. Do not use in production!**

- Self-signed certificates are used (not trusted by browsers)
- Default configurations are used for learning purposes
- Network policies should be hardened for production use
- Consider using cert-manager for automated certificate management
- Pod Security Admission is set to privileged for MetalLB (required for L2 mode)

## Requirements

| Component | Version | Purpose |
|-----------|---------|---------|
| K3s | Latest | Lightweight Kubernetes |
| MetalLB | v0.13.12+ | Load balancer |
| Traefik | v3.x | Ingress controller |
| Helm | v3.x | Package manager |
| Node.js | 18.x | Backend runtime |
| Docker/nerdctl | Latest | Container build |

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

This is an educational lab project. Feel free to fork and modify for your learning purposes.
