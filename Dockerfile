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
COPY --chmod=755 branding/rebrand.sh /docker-entrypoint.d/99-stratechna-rebrand.sh

# Patch icons.svg — substituir full-logo e logotype pelo logo Stratechna



# Patch icons.svg em bash puro — instalar python3 e fazer patch
RUN mkdir -p /var/lib/apt/lists/partial && apt-get update && apt-get install -y --no-install-recommends python3 && \
    python3 /tmp/patch-icons.py && \
    rm /tmp/patch-icons.py && \

    rm -rf /var/lib/apt/lists/*

# Injectar script para ocultar referências Zammad
COPY branding/hide_zammad_popup.js /opt/zammad/public/assets/hide_zammad_popup.js
COPY branding/index.html.erb       /opt/zammad/app/views/init/index.html.erb
