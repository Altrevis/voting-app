#!/usr/bin/env bash
# =============================================================================
# install-helm-components.sh
# Installe tous les composants Helm nécessaires pour le projet Voting App :
#   1. Nginx Ingress Controller
#   2. Redis (bitnami, mode standalone)
#   3. Azure Vote App (chart local)
#   4. (BONUS) KubeCost
#
# Prérequis :
#   - kubectl configuré et connecté à votre cluster AKS
#   - Helm 3.x installé (voir section ci-dessous si besoin)
# =============================================================================

set -euo pipefail

# --- Couleurs pour les logs -----------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
step() { echo -e "\n${CYAN}>>> $*${NC}"; }

# =============================================================================
# 0. INSTALLATION DE HELM (si absent)
# =============================================================================
step "0. Vérification / Installation de Helm"
if ! command -v helm &>/dev/null; then
  warn "Helm non trouvé. Installation via script officiel..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  log "Helm déjà installé : $(helm version --short)"
fi

# =============================================================================
# 1. NGINX INGRESS CONTROLLER
# =============================================================================
step "1. Nginx Ingress Controller"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=1 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --wait

log "Ingress Controller installé."
kubectl get svc -n ingress-nginx ingress-nginx-controller

# =============================================================================
# 2. REDIS (bitnami — mode standalone)
# =============================================================================
step "2. Redis"

REDIS_PASSWORD="1234"   # Doit correspondre à redis.password dans values.yaml

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install redis bitnami/redis \
  --namespace voting-app \
  --create-namespace \
  --set architecture=standalone \
  --set auth.password="${REDIS_PASSWORD}" \
  --set master.persistence.enabled=false \
  --wait

log "Redis installé. Service : redis-master (port 6379)"

# =============================================================================
# 3. AZURE VOTE APP (chart local)
# =============================================================================
step "3. Azure Vote App"

CHART_DIR="$(cd "$(dirname "$0")/azure-vote" && pwd)"

# Vérification que le chart existe
if [[ ! -f "${CHART_DIR}/Chart.yaml" ]]; then
  echo "Chart introuvable dans ${CHART_DIR}. Vérifiez le chemin." >&2
  exit 1
fi

helm upgrade --install azure-vote "${CHART_DIR}" \
  --namespace voting-app \
  --create-namespace \
  --set redis.host=redis-master \
  --set redis.password="${REDIS_PASSWORD}" \
  --wait

log "Azure Vote App installée."

# Afficher l'IP publique de l'Ingress
echo ""
log "En attente de l'IP externe de l'Ingress Controller..."
kubectl get ingress -n voting-app

# =============================================================================
# 4. (BONUS) KUBECOST
# =============================================================================
step "4. (BONUS) KubeCost"

helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm repo update

helm upgrade --install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="" \
  --wait

log "KubeCost installé."
log "Accès au dashboard : kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090"
log "Puis ouvrir http://localhost:9090"

# =============================================================================
# RÉSUMÉ
# =============================================================================
echo ""
log "=== Déploiement complet ==="
kubectl get pods -n ingress-nginx
kubectl get pods -n voting-app
kubectl get pods -n kubecost
