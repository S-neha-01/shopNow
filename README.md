# ShopNow E-Commerce - Kubernetes Deployment Project

ShopNow is a full-stack **MERN** (MongoDB, Express.js, React.js, Node.js) e-commerce application deployed on Kubernetes using raw manifests, a Helm chart, and an automated Jenkins CI/CD pipeline.

**Components:**
- **Frontend** — React customer shopping app (served via Nginx)
- **Admin** — React admin dashboard (served via Nginx)
- **Backend** — Express.js REST API (Node.js)
- **Database** — MongoDB (StatefulSet with persistent storage)

---

## Project Structure

```
shopNow/
├── backend/                        # Express.js API server
│   ├── Dockerfile
│   └── server.js
├── frontend/                       # React customer app
│   ├── Dockerfile
│   └── nginx/default.conf
├── admin/                          # React admin dashboard
│   ├── Dockerfile
│   └── nginx/default.conf
├── k8s/                            # Raw Kubernetes manifests
│   ├── namespace.yaml
│   ├── ingress.yaml
│   ├── mongodb/
│   │   ├── secret.yaml             # MongoDB credentials (base64)
│   │   ├── statefulset.yaml        # MongoDB StatefulSet + PVC
│   │   └── service.yaml            # Headless ClusterIP service
│   ├── backend/
│   │   ├── configmap.yaml          # PORT, NODE_ENV
│   │   ├── deployment.yaml         # 2 replicas + HPA + initContainer
│   │   └── service.yaml            # NodePort :30500
│   ├── frontend/
│   │   ├── deployment.yaml         # 2 replicas
│   │   └── service.yaml            # NodePort :30080
│   └── admin/
│       ├── deployment.yaml         # 1 replica
│       └── service.yaml            # NodePort :30081
├── helm/shopnow/                   # Helm chart (single umbrella chart)
│   ├── Chart.yaml
│   ├── values.yaml                 # All tuneable defaults
│   └── templates/
│       ├── _helpers.tpl            # Reusable template helpers
│       ├── namespace.yaml
│       ├── mongodb-secret.yaml
│       ├── mongodb-statefulset.yaml
│       ├── mongodb-service.yaml
│       ├── backend-configmap.yaml
│       ├── backend-deployment.yaml
│       ├── backend-service.yaml
│       ├── frontend-deployment.yaml
│       ├── frontend-service.yaml
│       ├── admin-deployment.yaml
│       ├── admin-service.yaml
│       └── ingress.yaml
├── Jenkinsfile                     # Groovy CI/CD pipeline
├── deploy-minikube.sh              # One-shot local deploy script
└── docs/                           # Architecture and setup guides
```

---

## Architecture Overview

```
                        ┌─────────────────────────────────────────┐
                        │            Kubernetes Cluster            │
                        │              (Minikube)                  │
                        │                                          │
Internet / Browser ────►│  Ingress (nginx)                        │
                        │    /           → frontend-service:80    │
                        │    /api/       → backend-service:5000   │
                        │    /admin-panel → admin-service:80      │
                        │                                          │
                        │  ┌──────────┐  ┌──────────┐            │
                        │  │ Frontend │  │  Admin   │            │
                        │  │ (nginx)  │  │ (nginx)  │            │
                        │  │ x2 pods  │  │ x1 pod   │            │
                        │  └──────────┘  └──────────┘            │
                        │                                          │
                        │  ┌────────────────────────────┐         │
                        │  │   Backend (Express.js)     │         │
                        │  │   x2 pods (HPA: 2-5)       │         │
                        │  └────────────┬───────────────┘         │
                        │               │                          │
                        │  ┌────────────▼───────────────┐         │
                        │  │   MongoDB (StatefulSet)     │         │
                        │  │   x1 pod + 1Gi PVC         │         │
                        │  └────────────────────────────┘         │
                        └─────────────────────────────────────────┘
```

### Port Reference

| Service | Container Port | NodePort | Protocol |
|---------|---------------|----------|----------|
| Frontend | 80 | 30080 | HTTP |
| Admin | 80 | 30081 | HTTP |
| Backend API | 5000 | 30500 | HTTP |
| MongoDB | 27017 | — (internal only) | TCP |

---

## Prerequisites

| Tool | Version Used | Purpose |
|------|-------------|---------|
| Docker | 29.1.2 | Build and run containers |
| Minikube | v1.36.0 | Local Kubernetes cluster |
| kubectl | v1.34.0 | Kubernetes CLI |
| Helm | v3.18.6 | Package manager for K8s |
| Git | 2.39.5 | Source control |
| Node.js | v22.11.0 | Build frontend/backend locally |

### Install Prerequisites (macOS)

```bash
brew install minikube kubectl helm git node
```

Verify everything is installed:

```bash
docker --version
minikube version
kubectl version --client
helm version
git --version
node --version
```

---

## Step 1 — Start Minikube

```bash
# Start with Docker driver (adjust memory to what Docker Desktop allows)
minikube start --driver=docker --memory=3500 --cpus=2

# Enable required addons
minikube addons enable ingress         # Path-based routing
minikube addons enable metrics-server  # Required for HPA (auto-scaling)

# Verify cluster is running
minikube status
kubectl get nodes
```

---

## Step 2 — Build Docker Images

The images must be built inside Minikube's Docker daemon so Kubernetes can find them without a remote registry.

```bash
# Point your shell's Docker CLI at Minikube's daemon
# Run this in every new terminal session
eval $(minikube docker-env)

# Clone the source repository
git clone https://github.com/S-neha-01/shopNow.git
cd shopNow

# Build all three images
docker build -t shopnow/backend:latest  backend/

docker build \
  --build-arg REACT_APP_API_BASE_URL=/api \
  -t shopnow/frontend:latest frontend/

docker build \
  --build-arg REACT_APP_API_BASE_URL=/api \
  -t shopnow/admin:latest admin/

# Verify images are available inside Minikube
docker images | grep shopnow
```

---

## Step 3 — Deploy to Kubernetes

Choose **one** of the two options below.

### Option A — Raw Kubernetes Manifests

Apply resources in dependency order (namespace → database → backend → frontend/admin → ingress):

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/mongodb/
kubectl apply -f k8s/backend/
kubectl apply -f k8s/frontend/
kubectl apply -f k8s/admin/
kubectl apply -f k8s/ingress.yaml
```

Wait for all pods to be ready:

```bash
kubectl wait --for=condition=ready pod -l app=mongodb  -n shopnow --timeout=120s
kubectl wait --for=condition=ready pod -l app=backend  -n shopnow --timeout=120s
kubectl wait --for=condition=ready pod -l app=frontend -n shopnow --timeout=60s
kubectl wait --for=condition=ready pod -l app=admin    -n shopnow --timeout=60s
```

### Option B — Helm Chart (Recommended)

```bash
# Install / upgrade in one command
helm upgrade --install shopnow ./helm/shopnow \
  --namespace shopnow \
  --create-namespace \
  --set global.imagePullPolicy=Never \
  --wait \
  --timeout 5m

# To override MongoDB password
helm upgrade --install shopnow ./helm/shopnow \
  --namespace shopnow \
  --create-namespace \
  --set global.imagePullPolicy=Never \
  --set mongodb.auth.rootPassword=mypassword
```

Useful Helm commands:

```bash
helm list -n shopnow              # List installed releases
helm status shopnow -n shopnow    # Check release status
helm get values shopnow -n shopnow # View applied values
helm uninstall shopnow -n shopnow  # Remove all resources
```

### Option C — One-Shot Script

```bash
chmod +x deploy-minikube.sh

./deploy-minikube.sh          # Uses raw manifests
./deploy-minikube.sh --helm   # Uses Helm chart
```

---

## Step 4 — Verify the Deployment

```bash
# Check all pods are Running
kubectl get pods -n shopnow

# Expected output:
# NAME                        READY   STATUS    RESTARTS
# mongodb-0                   1/1     Running   0
# backend-xxxx-xxxx           1/1     Running   0
# backend-xxxx-xxxx           1/1     Running   0
# frontend-xxxx-xxxx          1/1     Running   0
# frontend-xxxx-xxxx          1/1     Running   0
# admin-xxxx-xxxx             1/1     Running   0

# Check services and NodePorts
kubectl get svc -n shopnow

# Check HPA (auto-scaler)
kubectl get hpa -n shopnow

# Check ingress
kubectl get ingress -n shopnow

# Check everything at once
kubectl get all -n shopnow
```

---

## Step 5 — Access the Application

```bash
# Get Minikube IP
minikube ip
# Example: 192.168.49.2
```

| Application | URL |
|-------------|-----|
| Frontend (Customer App) | `http://<minikube-ip>:30080` |
| Admin Dashboard | `http://<minikube-ip>:30081` |
| Backend API Health | `http://<minikube-ip>:30500/api/health` |
| Backend API Products | `http://<minikube-ip>:30500/api/products` |

**Using Ingress (path-based routing):**

```bash
# Add Minikube IP to /etc/hosts for hostname-based access
echo "$(minikube ip) shopnow.local" | sudo tee -a /etc/hosts

# Then access via:
# http://shopnow.local/              → Frontend
# http://shopnow.local/api/health    → Backend
# http://shopnow.local/admin-panel/  → Admin

# Or use minikube tunnel (runs in background)
minikube tunnel
```

---

## Step 6 — Jenkins CI/CD Pipeline

The `Jenkinsfile` at the repo root defines a full CI/CD pipeline with these stages:

| Stage | What it does |
|-------|-------------|
| **Checkout** | Clones the repo, resolves image tag from Git SHA |
| **Test** | Runs `npm test` for backend, frontend, and admin in parallel |
| **Build Images** | Builds all 3 Docker images in parallel |
| **Push Images** | Pushes tagged + `latest` images to Docker registry |
| **Deploy** | Deploys via Helm (`--atomic`) or `kubectl set image` |
| **Verify** | Port-forwards backend, calls `/api/health`, fails pipeline if non-200 |
| **Post** | Cleans local images, workspace; prints success/failure summary |

### Jenkins Setup

1. **Install Jenkins** (or run via Docker):
   ```bash
   docker run -d -p 8080:8080 -p 50000:50000 \
     -v jenkins_home:/var/jenkins_home \
     jenkins/jenkins:lts
   ```

2. **Add Credentials** in Jenkins → Manage Jenkins → Credentials:

   | Credential ID | Type | Value |
   |---|---|---|
   | `dockerhub-credentials` | Username/Password | Your DockerHub login |
   | `kubeconfig-secret` | Secret file | Your `~/.kube/config` |
   | `github-credentials` | Username/Password | Your GitHub login |

3. **Create a Pipeline Job**:
   - New Item → Pipeline
   - Pipeline → Definition: `Pipeline script from SCM`
   - SCM: Git → Repository URL: `https://github.com/S-neha-01/shopNow`
   - Script Path: `Jenkinsfile`
   - Save → Build Now

4. **Pipeline parameters** (configurable from the Jenkins UI):
   - `IMAGE_TAG` — defaults to short Git SHA
   - `DOCKER_REGISTRY` — your registry prefix (e.g. `docker.io/yourorg`)
   - `DEPLOY_VIA_HELM` — true/false
   - `RUN_TESTS` — true/false
   - `DEPLOY_ENV` — `staging` or `production`

---

## Helm Chart — Configuration Reference

All values can be overridden with `--set key=value` or a custom `values.yaml`.

```yaml
# values.yaml highlights

global:
  namespace: shopnow
  imagePullPolicy: IfNotPresent

mongodb:
  auth:
    rootPassword: rootpassword   # CHANGE IN PRODUCTION
  persistence:
    size: 1Gi

backend:
  replicas: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 5
    targetCPUUtilizationPercentage: 70

frontend:
  replicas: 2

admin:
  replicas: 1

ingress:
  enabled: true
  className: nginx
```

---

## Kubernetes Design Decisions

| Decision | Reason |
|---|---|
| **MongoDB as StatefulSet** | Stable network identity, ordered startup, PVC persists data across pod restarts |
| **Headless Service for MongoDB** | Enables `mongodb-0.mongodb-service` DNS — required by StatefulSet |
| **initContainer on backend** | Backend waits for MongoDB port 27017 to be ready before starting |
| **NodePort services** | Works out-of-the-box on Minikube without a cloud load balancer |
| **HPA on backend (2–5 replicas)** | Backend is the most CPU-intensive component — auto-scales at 70% CPU |
| **RollingUpdate on all Deployments** | `maxUnavailable: 0` ensures zero-downtime deploys |
| **Secrets for MongoDB URI** | Full connection string stored in a K8s Secret, never in ConfigMap plaintext |
| **Single umbrella Helm chart** | Simpler to manage one release vs. 4 separate chart installs |

---

## Debugging Guide

```bash
# Pod not starting — describe it for events
kubectl describe pod <pod-name> -n shopnow

# Check logs
kubectl logs <pod-name> -n shopnow
kubectl logs <pod-name> -n shopnow --previous   # crashed container logs

# MongoDB shell access
kubectl exec -it mongodb-0 -n shopnow -- mongosh \
  -u root -p rootpassword --authenticationDatabase admin

# Check resource usage (requires metrics-server)
kubectl top pods -n shopnow
kubectl top nodes

# HPA not scaling — check metrics
kubectl describe hpa backend-hpa -n shopnow

# Re-deploy after fixing an issue
kubectl rollout restart deployment/backend  -n shopnow
kubectl rollout restart deployment/frontend -n shopnow
kubectl rollout restart deployment/admin    -n shopnow

# Roll back to previous version
kubectl rollout undo deployment/backend -n shopnow
```

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/products` | List products (supports search/filter/pagination) |
| GET | `/api/products/:id` | Get single product |
| POST | `/api/products` | Create product |
| PUT | `/api/products/:id` | Update product |
| DELETE | `/api/products/:id` | Delete product |
| POST | `/api/invoices` | Create order |
| GET | `/api/invoices` | List orders |
| PUT | `/api/invoices/:id/status` | Update order status |
| GET | `/api/analytics/dashboard` | Sales analytics |
| POST | `/api/seed/products` | Seed sample data |

---

## Additional Documentation

- [docs/APPLICATION-ARCHITECTURE.md](docs/APPLICATION-ARCHITECTURE.md)
- [docs/K8S-CONCEPTS.md](docs/K8S-CONCEPTS.md)
- [docs/TOOLS-SETUP-GUIDE.md](docs/TOOLS-SETUP-GUIDE.md)
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

## Author

**K Mohan Krishna** — original application
**Sneha** — Kubernetes deployment, Helm chart, Jenkins CI/CD pipeline
