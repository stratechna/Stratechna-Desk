#!/bin/bash
# /docker-entrypoint.d/99-stratechna-rebrand.sh
# Substitui strings "Zammad" por "Stratechna Desk" nos assets compilados em runtime
# Executado antes do arranque do Zammad pelo entrypoint base

set -e

ASSETS_DIR="/opt/zammad/public/assets"

echo "[Stratechna] A aplicar branding..."

# Substituir nome da app nos ficheiros JS/HTML compilados
if [ -d "$ASSETS_DIR" ]; then
  find "$ASSETS_DIR" -type f \( -name "*.js" -o -name "*.html" \) | while read f; do
    sed -i 's/Zammad/Stratechna Desk/g' "$f" 2>/dev/null || true
    sed -i 's/zammad/stratechna-desk/g' "$f" 2>/dev/null || true
  done
fi

# Substituir no título da página em views ERB (se acessíveis)
VIEWS_DIR="/opt/zammad/app/views"
if [ -d "$VIEWS_DIR" ]; then
  find "$VIEWS_DIR" -type f -name "*.erb" | while read f; do
    sed -i 's/Zammad/Stratechna Desk/g' "$f" 2>/dev/null || true
  done
fi

# Definir nome da organização via env se ZAMMAD_FQDN não estiver definido
if [ -z "$ZAMMAD_FQDN" ] && [ -n "$DESK_SLUG" ]; then
  export ZAMMAD_FQDN="${DESK_SLUG}.desk.stratechna.com"
fi

echo "[Stratechna] Branding aplicado."
