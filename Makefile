# Makefile – centralised DevOps tasks
include versions.env
export K3S_VERSION ISTIO_VERSION METALLB_VERSION TRAEFIK_VERSION

.PHONY: install-k3s uninstall-k3s deploy install-istio install-metallb install-traefik deploy-app

install-k3s:
	@./scripts/install_k3s.sh

uninstall-k3s:
	@./scripts/uninstall_all.sh

deploy: install-istio install-metallb install-traefik deploy-app
	@echo "✅ All components deployed"

install-istio:
	curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$(ISTIO_VERSION) sh -
	./istio-$(ISTIO_VERSION)/bin/istioctl install --set profile=demo -y
	kubectl label namespace default istio-injection=enabled --overwrite

install-metallb:
	helm repo add metallb https://metallb.github.io/metallb
	helm repo update
	helm upgrade --install metallb metallb/metallb \
	  --namespace metallb-system --create-namespace \
	  --set speaker.nodeSelector."kubernetes\.io/os"=linux \
	  --set controller.nodeSelector."kubernetes\.io/os"=linux

install-traefik:
	helm repo add traefik https://traefik.github.io/charts
	helm repo update
	helm upgrade --install traefik traefik/traefik \
	  --namespace traefik --create-namespace \
	  --set deployment.kind=DaemonSet \
	  --set service.type=LoadBalancer

deploy-app:
	kubectl apply -k backend/k8s
	kubectl apply -f backend/k8s/ingress-updated.yaml