#!/usr/bin/env bash
# ============================================================
# deploy-minikube.sh — One-shot local deploy on Minikube
#
# Usage:
#   chmod +x deploy-minikube.sh
#   ./deploy-minikube.sh          # raw k8s manifests
#   ./deploy-minikube.sh --helm   # Helm chart
# ============================================================
set -euo pipefail

USE_HELM=false
[[ "${1:-}" == "--helm" ]] && USE_HELM=true

SHOPNOW_REPO="https://github.com/mohanDevOps-arch/shopNow.git"
NAMESPACE="shopnow"

echo "======================================================"
echo " ShopNow — Minikube Deployment"
echo "======================================================"

# ── 1. Ensure Minikube is running ──────────────────────────
if ! minikube status | grep -q "Running"; then
    echo "[1/6] Starting Minikube..."
    minikube start --driver=docker --memory=4096 --cpus=2
else
    echo "[1/6] Minikube already running."
fi

# ── 2. Enable required addons ──────────────────────────────
echo "[2/6] Enabling Minikube addons..."
minikube addons enable ingress
minikube addons enable metrics-server

# ── 3. Point Docker daemon at Minikube's registry ──────────
echo "[3/6] Configuring Docker to use Minikube's daemon..."
eval "$(minikube docker-env)"

# ── 4. Clone and build images inside Minikube ──────────────
echo "[4/6] Building Docker images..."

if [ ! -d "shopNow" ]; then
    git clone "$SHOPNOW_REPO" shopNow
fi

docker build -t shopnow/backend:latest  shopNow/backend/
docker build \
    --build-arg REACT_APP_API_BASE_URL=/api \
    -t shopnow/frontend:latest shopNow/frontend/
docker build \
    --build-arg REACT_APP_API_BASE_URL=/api \
    -t shopnow/admin:latest shopNow/admin/

echo "Images built:"
docker images | grep shopnow

# ── 5. Deploy ──────────────────────────────────────────────
echo "[5/6] Deploying to Kubernetes..."

if $USE_HELM; then
    echo "  → Using Helm chart"
    helm upgrade --install shopnow ./helm/shopnow \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --set global.imagePullPolicy=Never \
        --wait --timeout 5m
else
    echo "  → Using raw manifests"
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/mongodb/
    kubectl apply -f k8s/backend/
    kubectl apply -f k8s/frontend/
    kubectl apply -f k8s/admin/
    kubectl apply -f k8s/ingress.yaml

    echo "  Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=mongodb  -n "$NAMESPACE" --timeout=120s
    kubectl wait --for=condition=ready pod \
        -l app=backend  -n "$NAMESPACE" --timeout=120s
    kubectl wait --for=condition=ready pod \
        -l app=frontend -n "$NAMESPACE" --timeout=60s
fi

# ── 6. Print access URLs ───────────────────────────────────
echo ""
echo "[6/6] Deployment complete!"
echo "======================================================"
MINIKUBE_IP=$(minikube ip)
echo ""
echo "  NodePort access:"
echo "    Frontend  → http://${MINIKUBE_IP}:30080"
echo "    Admin     → http://${MINIKUBE_IP}:30081"
echo "    Backend   → http://${MINIKUBE_IP}:30500/api/health"
echo ""
echo "  Ingress access (add to /etc/hosts if needed):"
echo "    echo \"${MINIKUBE_IP} shopnow.local\" | sudo tee -a /etc/hosts"
echo "    http://shopnow.local/"
echo ""
echo "  Or use minikube service tunnel:"
echo "    minikube service frontend-service -n $NAMESPACE --url"
echo ""
echo "  Pod status:"
kubectl get pods -n "$NAMESPACE"
echo "======================================================"
