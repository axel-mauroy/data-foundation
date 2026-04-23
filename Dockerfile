# Utilisation d'une image minimaliste pré-configurée pour Python
FROM python:3.11-slim

# Copier uv depuis l'image officielle (le binaire est à /uv)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/bin/uv

# Installation de 'just' (nécessite curl) et nettoyage immédiat pour réduire la taille
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin \
    && apt-get purge -y --auto-remove curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Optimisations uv et Python
ENV UV_COMPILE_BYTECODE=1
ENV UV_NO_CACHE=1
ENV PYTHONUNBUFFERED=1

# Copie des fichiers de dépendances en premier pour le cache Docker
COPY pyproject.toml uv.lock ./

# Installation des dépendances sans le code source
RUN uv sync --frozen --no-dev --no-install-project

# Copie du code source complet
COPY . .

# Installation finale (lie le projet à l'environnement)
RUN uv sync --frozen --no-dev

# Activation de l'environnement virtuel dans le PATH
ENV PATH="/app/.venv/bin:$PATH"

# ENTRYPOINT corrigé (just est maintenant installé)
ENTRYPOINT ["just"]
CMD ["--list"]
