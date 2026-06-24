#!/usr/bin/env bash
# =============================================================================
# setup-local-minikube.sh
# Remplace Azure AKS par un cluster Kubernetes LOCAL avec Minikube.
#
# Ce script :
#   1. Installe Minikube (si absent)
#   2. Installe kubectl (si absent)
#   3. Installe Helm (si absent)
#   4. Démarre le cluster Minikube
#   5. Installe Nginx Ingress Controller via Helm
#   6. Installe Redis via Helm (bitnami)
#   7. Déploie l'Azure Vote App via le chart local
#   8. Configure /etc/hosts pour azure-vote.local
#
# Prérequis : Docker installé et en cours d'exécution
# =============================================================================

set -euo pipefail

# --- Couleurs ----------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
step()  { echo -e "\n${CYAN}>>> $*${NC}"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

REDIS_PASSWORD="1234"
CHART_DIR="$(cd "$(dirname "$0")/azure-vote" && pwd)"
NAMESPACE="voting-app"
HOST="azure-vote.local"

# =============================================================================
# 1. VÉRIFICATION DE DOCKER
# =============================================================================
step "1. Vérification de Docker"
if ! command -v docker &>/dev/null; then
  error "Docker non trouvé. Installez Docker Desktop ou Docker Engine avant de continuer."
fi
if ! docker info &>/dev/null; then
  error "Docker n'est pas démarré. Lancez Docker puis relancez ce script."
fi
log "Docker OK : $(docker version --format '{{.Server.Version}}')"

# =============================================================================
# 2. INSTALLATION DE MINIKUBE (si absent)
# =============================================================================
step "2. Vérification / Installation de Minikube"
if ! command -v minikube &>/dev/null; then
  warn "Minikube non trouvé. Installation..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
  rm minikube-linux-amd64
  log "Minikube installé."
else
  log "Minikube déjà installé : $(minikube version --short)"
fi

# =============================================================================
# 3. INSTALLATION DE KUBECTL (si absent)
# =============================================================================
step "3. Vérification / Installation de kubectl"
if ! command -v kubectl &>/dev/null; then
  warn "kubectl non trouvé. Installation..."
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
  log "kubectl installé."
else
  log "kubectl déjà installé : $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

# =============================================================================
# 4. INSTALLATION DE HELM (si absent)
# =============================================================================
step "4. Vérification / Installation de Helm"
if ! command -v helm &>/dev/null; then
  warn "Helm non trouvé. Installation via script officiel..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  log "Helm déjà installé : $(helm version --short)"
fi

# =============================================================================
# 5. DÉMARRAGE DU CLUSTER MINIKUBE
# =============================================================================
step "5. Démarrage de Minikube"
if minikube status &>/dev/null 2>&1 | grep -q "Running"; then
  log "Minikube est déjà en cours d'exécution."
else
  log "Démarrage du cluster Minikube avec le driver Docker..."
  minikube start \
    --driver=docker \
    --cpus=2 \
    --memory=4096 \
    --kubernetes-version=stable
  log "Cluster Minikube démarré."
fi

# Vérification que kubectl pointe sur minikube
kubectl config use-context minikube
log "Contexte kubectl : $(kubectl config current-context)"
kubectl get nodes

# =============================================================================
# 6. NGINX INGRESS CONTROLLER (via Helm)
# =============================================================================
step "6. Nginx Ingress Controller (Helm)"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=1 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.type=NodePort \
  --wait --timeout=120s

log "Nginx Ingress Controller installé."
kubectl get svc -n ingress-nginx ingress-nginx-controller

# =============================================================================
# 7. REDIS (bitnami — standalone)
# =============================================================================
step "7. Redis (Helm bitnami)"

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install redis bitnami/redis \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set architecture=standalone \
  --set auth.password="${REDIS_PASSWORD}" \
  --set master.persistence.enabled=false \
  --wait --timeout=120s

log "Redis installé. Service : redis-master (port 6379)"

# =============================================================================
# 8. AZURE VOTE APP (chart local)
# =============================================================================
step "8. Azure Vote App (chart local)"

if [[ ! -f "${CHART_DIR}/Chart.yaml" ]]; then
  error "Chart introuvable dans ${CHART_DIR}."
fi

helm upgrade --install azure-vote "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --set redis.host=redis-master \
  --set redis.password="${REDIS_PASSWORD}" \
  --wait --timeout=120s

log "Azure Vote App déployée."
kubectl get pods -n "${NAMESPACE}"
kubectl get svc  -n "${NAMESPACE}"
kubectl get ingress -n "${NAMESPACE}"

# =============================================================================
# 9. CONFIGURATION /etc/hosts
# =============================================================================
step "9. Configuration de /etc/hosts"

# Récupérer l'IP du nœud Minikube
MINIKUBE_IP=$(minikube ip)
log "IP Minikube : ${MINIKUBE_IP}"

# Vérifier si l'entrée existe déjà
if grep -q "${HOST}" /etc/hosts; then
  warn "Entrée '${HOST}' déjà présente dans /etc/hosts — mise à jour."
  sudo sed -i "/${HOST}/d" /etc/hosts
fi

echo "${MINIKUBE_IP}  ${HOST}" | sudo tee -a /etc/hosts > /dev/null
log "Ajouté dans /etc/hosts : ${MINIKUBE_IP}  ${HOST}"

# =============================================================================
# RÉSUMÉ FINAL
# =============================================================================
echo ""
echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN}  Déploiement local terminé avec succès !${NC}"
echo -e "${GREEN}=========================================================${NC}"
echo ""
log "Pods en cours d'exécution :"
kubectl get pods -n ingress-nginx
kubectl get pods -n "${NAMESPACE}"
echo ""
echo -e "${CYAN}  Accès à l'application :${NC}"
echo -e "  ${GREEN}http://${HOST}${NC}"
echo ""
echo -e "${CYAN}  Si l'application n'est pas accessible, lancez dans un autre terminal :${NC}"
echo -e "  ${YELLOW}minikube tunnel${NC}  (maintenir en arrière-plan)"
echo ""
echo -e "${CYAN}  Pour arrêter le cluster :${NC}"
echo -e "  ${YELLOW}minikube stop${NC}"
echo -e "${GREEN}=========================================================${NC}"
