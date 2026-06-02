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