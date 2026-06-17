FROM ghcr.io/zammad/zammad:latest

LABEL org.opencontainers.image.title="Stratechna Desk"
LABEL org.opencontainers.image.vendor="Stratechna"
LABEL org.opencontainers.image.source="https://github.com/stratechna/Stratechna-Desk"

# Branding assets
COPY branding/logo.svg         /opt/zammad/public/assets/images/logo.svg
COPY branding/logo.svg         /opt/zammad/public/assets/images/logo-white.svg
COPY branding/favicon.png      /opt/zammad/public/favicon.png

# Custom CSS — injecta cores Stratechna
COPY branding/stratechna.css   /opt/zammad/app/assets/stylesheets/application_custom.scss

# Patch de nome da app (substitui "Zammad" por "Stratechna Desk" nos strings JS compilados)
# Feito em runtime via entrypoint para não depender de rebuild do assets pipeline
COPY branding/rebrand.sh       /docker-entrypoint.d/99-stratechna-rebrand.sh
RUN chmod +x /docker-entrypoint.d/99-stratechna-rebrand.sh
