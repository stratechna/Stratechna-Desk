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

# Patch CSS — dimensões correctas para logotype e full-logo
COPY branding/application.css /opt/zammad/public/assets/application-1777b10035b454d670de0d71eee6caefad1d06e4206d92faa3dfd486b5be4264.css
COPY branding/svg-dimensions.css /opt/zammad/public/assets/svg-dimensions-9301635de4462b296da1f4ec32c0e4b6d7578e9a49bbe5eb387b57d317bdea6c.css
COPY branding/favicon.ico /opt/zammad/public/favicon.ico
COPY branding/application.js /opt/zammad/public/assets/application-710831abbe58cd003d1da50e6d8133e60a2c7e9556d89fc3c30bd0d86dda39e4.js
