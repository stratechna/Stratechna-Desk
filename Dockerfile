FROM ghcr.io/zammad/zammad:latest

LABEL org.opencontainers.image.title="Stratechna Desk"
LABEL org.opencontainers.image.vendor="Stratechna"
LABEL org.opencontainers.image.source="https://github.com/stratechna/Stratechna-Desk"

# Branding assets
COPY branding/logo.svg             /opt/zammad/public/assets/images/logo.svg
COPY branding/logo.svg             /opt/zammad/public/assets/images/logo-white.svg
COPY branding/favicon.png          /opt/zammad/public/favicon.png
COPY branding/stratechna.css       /opt/zammad/app/assets/stylesheets/application_custom.scss
COPY branding/icons.svg            /opt/zammad/public/assets/images/icons.svg
COPY branding/hide_zammad_popup.js /opt/zammad/public/assets/hide_zammad_popup.js
COPY branding/index.html.erb       /opt/zammad/app/views/init/index.html.erb
COPY --chmod=755 branding/rebrand.sh /docker-entrypoint.d/99-stratechna-rebrand.sh
