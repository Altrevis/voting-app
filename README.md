# Azure Voting App
> **Attention:** Ce projet sera utilisé tout au long du module, gardez toujours votre travail, même s'il ne fonctionne pas, ça vous permettra de comparer avec les corrections et de comprendre ce qu'il vous manque !

## Introduction
L'application Azure vote app est une application très simple qui permet de voter entre deux choix définit dans le fichier `config_file.cfg`
Le choix est stocké dans une base de données de type Cache (Redis).

## Prérequis
Pour faire fonctionner le code en local vous avez besoin de:
- Python (3.13 minimum)
- Redis

Certaines dépendances doivent être installé avec Pip, le gestionnaire de packages de Python:
- flask
- redis

> **Recommendations**: Je vous conseille d'utiliser les virtualenv de Python pour garder votre machine clean.

## Lancer le projet

Depuis votre terminal une fois les dépendances configuré, lancer la commande `python main.py` pensez a ajouter la variable d'environnement `REDIS` qui pointe vers le serveur Redis et `REDIS_PWD` si vous avez un mot de passe sur votre Cache Redis 

### Conteneurisation avec Docker

L'application a été conteneurisée avec Docker. Un `Dockerfile` a été ajouté dans le dossier `azure-vote/`.

#### Variables d'environnement

|-------------|------------------------------------|-------------------|
| Variable    | Description                        | Valeur par défaut |
|-------------|------------------------------------|-------------------|
| `REDIS`     | Adresse du serveur Redis           | `redis`           |
| `REDIS_PWD` | Mot de passe pour  Redis           | `"1234"`          |
|-------------|------------------------------------|-------------------|

#### Lancer avec Docker Compose

Un fichier `docker-compose.yml` est disponible à la racine du projet. Il lance automatiquement :
- un container **Redis** (avec mot de passe)
- un container **azure-vote** (build depuis le Dockerfile)

Les deux services disposent d'un **healthcheck** :
- Redis : vérifié via `redis-cli ping`
- azure-vote : vérifié via une requête HTTP sur le port 80

```bash
sudo docker compose up --build
```

L'application est ensuite accessible sur [http://localhost:8080](http://localhost:8080).

## CI/CD - GitHub Actions

[![CI - Build, Scout & Push](https://github.com/Altrevis/voting-app/actions/workflows/docker-build-scout-push.yml/badge.svg)](https://github.com/Altrevis/voting-app/actions/workflows/docker-build-scout-push.yml)

Un workflow GitHub Actions se déclenche automatiquement à chaque push sur la branche `main`.

### Étapes du pipeline

| Étape | Description |
|---|---|
| **Checkout** | Récupération du code source |
| **Login Docker Hub** | Authentification via les secrets GitHub |
| **Docker Build** | Construction de l'image depuis `./azure-vote` |
| **Docker Scout** | Scan des vulnérabilités CVE (critiques et hautes) |
| **Docker Push** | Publication sur Docker Hub avec les tags `latest` et `<sha>` |

### Image Dockermise à jour du README pour la partie CI / CD
CI - Build, Scout & Push #3: Commit 2586f45 pushed by Altrevis
main	
1 minute ago
 24s

L'image est disponible sur Docker Hub :

```bash
docker pull altrevis/voting-app:latest
```

### Secrets GitHub requis

| Secret | Description |
|---|---|
| `DOCKERHUB_USERNAME` | Nom d'utilisateur Docker Hub |
| `DOCKERHUB_TOKEN` | Access token Docker Hub (Personal access tokens) |

## Déploiement Kubernetes avec Helm

### Prérequis

- [Docker](https://docs.docker.com/engine/install/) installé et démarré
- [Minikube](https://minikube.sigs.k8s.io/docs/start/) (cluster local) **ou** un cluster AKS (Azure)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configuré
- [Helm 3](https://helm.sh/docs/intro/install/)

### Structure du chart

```
helm/
├── install-helm-components.sh   # Script d'installation pour AKS
├── setup-local-minikube.sh      # Script d'installation pour Minikube (local)
└── azure-vote/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── deployment.yaml
        ├── service.yaml
        ├── ingress.yaml
        ├── secret.yaml
        └── _helpers.tpl
```

### Déploiement local avec Minikube

#### 1. Démarrer Minikube

```bash
minikube start --driver=docker --cpus=2 --memory=4096
```

#### 2. Construire l'image dans le Docker de Minikube

L'image n'étant pas publiée sur Docker Hub, elle doit être construite directement dans l'environnement Docker interne de Minikube (`pullPolicy: Never`) :

```bash
eval $(minikube docker-env)
docker build -t altrevis/azure-vote:latest ./azure-vote/
```

#### 3. Déployer tous les composants

```bash
cd helm/
bash install-helm-components.sh
```

Ce script installe dans l'ordre :
1. **Nginx Ingress Controller** via Helm
2. **Redis** (bitnami, mode standalone) via Helm
3. **Azure Vote App** via le chart local

#### 4. Activer le tunnel (LoadBalancer)

Dans un terminal dédié, laisser tourner :

```bash
minikube tunnel
```

#### 5. Configurer `/etc/hosts`

Récupérer l'External-IP attribuée par le tunnel :

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Colonne EXTERNAL-IP → ex: 10.105.94.101
```

Ajouter la ligne dans `/etc/hosts` :

```bash
echo "<EXTERNAL-IP>  azure-vote.local" | sudo tee -a /etc/hosts
```

L'application est ensuite accessible sur [http://azure-vote.local](http://azure-vote.local).

> Le terminal `minikube tunnel` doit rester actif pour que l'IP reste joignable.

### Déploiement sur Azure AKS

```bash
# Connexion au cluster AKS
az aks get-credentials --resource-group <rg> --name <cluster>

cd helm/
bash install-helm-components.sh
```

### Composants Helm installés

| Composant | Chart | Namespace |
|---|---|---|
| Nginx Ingress Controller | `ingress-nginx/ingress-nginx` | `ingress-nginx` |
| Redis | `bitnami/redis` (standalone) | `voting-app` |
| Azure Vote App | chart local `helm/azure-vote` | `voting-app` |

### Paramètres configurables (`values.yaml`)

| Paramètre | Description | Défaut |
|---|---|---|
| `image.repository` | Image Docker de l'app | `altrevis/azure-vote` |
| `image.tag` | Tag de l'image | `latest` |
| `replicaCount` | Nombre de réplicas | `1` |
| `redis.host` | Hostname du service Redis | `redis-master` |
| `redis.password` | Mot de passe Redis | `1234` |
| `app.title` | Titre affiché | `Voting App` |
| `app.vote1` | Libellé du vote 1 | `Cats` |
| `app.vote2` | Libellé du vote 2 | `Dogs` |
| `ingress.hosts[0].host` | Nom de domaine | `azure-vote.local` |

### Vérifications post-déploiement

```bash
# État des pods
kubectl get pods -n voting-app
kubectl get pods -n ingress-nginx

# Ingress et services
kubectl get ingress -n voting-app
kubectl get svc -n voting-app

# Releases Helm installées
helm list -n voting-app

# Logs de l'application
kubectl logs -n voting-app -l app.kubernetes.io/name=azure-vote --tail=50

# Test Redis
kubectl exec -it -n voting-app \
  $(kubectl get pod -n voting-app -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}') \
  -- redis-cli -a 1234 ping
```