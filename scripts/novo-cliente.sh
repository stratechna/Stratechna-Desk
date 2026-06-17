#!/bin/bash
# /opt/stratechna/desk/scripts/novo-cliente.sh
# Uso: bash novo-cliente.sh <slug> <email-admin> [empresa] [dominio-proprio]
#
# Exemplos:
#   bash novo-cliente.sh esferancora admin@esferancora.pt "Esferancora Lda"
#   bash novo-cliente.sh esferancora admin@esferancora.pt "Esferancora Lda" desk.esferancora.pt

set -e

SLUG="$1"
EMAIL="$2"
EMPRESA="${3:-$SLUG}"
DOMINIO_PROPRIO="$4"

TEMPLATE_DIR="/opt/stratechna/desk/template"
CLIENTES_DIR="/opt/stratechna/desk/clientes"
INSTANCE_DIR="${CLIENTES_DIR}/${SLUG}"
SCRIPTS_DIR="/opt/stratechna/desk/scripts"

# ── Validação ──────────────────────────────────────────────────────────────────
if [ -z "$SLUG" ] || [ -z "$EMAIL" ]; then
  echo "Uso: $0 <slug> <email-admin> [empresa] [dominio-proprio]"
  exit 1
fi

if [ -d "$INSTANCE_DIR" ]; then
  echo "ERRO: instância '${SLUG}' já existe em ${INSTANCE_DIR}"
  exit 1
fi

echo "▶ Stratechna Desk — novo cliente: ${SLUG}"

# ── Gerar credenciais ──────────────────────────────────────────────────────────
DESK_SECRET=$(openssl rand -hex 32)
DESK_DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

# ── Criar directório da instância ──────────────────────────────────────────────
mkdir -p "${INSTANCE_DIR}"

# ── Gerar .env ─────────────────────────────────────────────────────────────────
cat > "${INSTANCE_DIR}/.env" << ENV
CLIENTE=${SLUG}
DESK_EMAIL=${EMAIL}
DESK_EMPRESA=${EMPRESA}
DESK_SECRET=${DESK_SECRET}
DESK_DB_PASS=${DESK_DB_PASS}
ENV

# ── Regra domínio próprio para Traefik ────────────────────────────────────────
if [ -n "$DOMINIO_PROPRIO" ]; then
  EXTRA_HOSTS_RULE=" || Host(\`${DOMINIO_PROPRIO}\`)"
else
  EXTRA_HOSTS_RULE=""
fi

# ── Gerar docker-compose.yml da instância ─────────────────────────────────────
sed \
  -e "s/\${CLIENTE}/${SLUG}/g" \
  -e "s/\${DESK_SECRET}/${DESK_SECRET}/g" \
  -e "s/\${DESK_DB_PASS}/${DESK_DB_PASS}/g" \
  -e "s|\${EXTRA_HOSTS_RULE}|${EXTRA_HOSTS_RULE}|g" \
  "${TEMPLATE_DIR}/docker-compose.yml" > "${INSTANCE_DIR}/docker-compose.yml"

# ── DNS via PowerDNS ──────────────────────────────────────────────────────────
echo "▶ A registar DNS: ${SLUG}.desk.stratechna.com → 95.217.8.239"
bash "${SCRIPTS_DIR}/dns-add.sh" "${SLUG}.desk" "${SLUG}.desk.stratechna.com"

# ── Arrancar containers ───────────────────────────────────────────────────────
echo "▶ A arrancar containers..."
cd "${INSTANCE_DIR}"
docker compose pull
docker compose up -d

# ── Aguardar Zammad estar pronto ──────────────────────────────────────────────
echo "▶ A aguardar inicialização do Zammad (pode demorar 60-90s)..."
sleep 30
RETRIES=12
for i in $(seq 1 $RETRIES); do
  STATUS=$(docker exec desk-${SLUG}-web curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    echo "✓ Zammad pronto."
    break
  fi
  echo "  ... aguardar (tentativa ${i}/${RETRIES})"
  sleep 15
done

# ── Configuração inicial via API Zammad ───────────────────────────────────────
echo "▶ A configurar organização e admin..."
docker exec desk-${SLUG}-web bundle exec rake zammad:setup:base \
  ZAMMAD_FQDN="${SLUG}.desk.stratechna.com" 2>/dev/null || true

# Criar admin via rails console
docker exec desk-${SLUG}-web bundle exec rails r "
  User.create_if_not_exists(
    login: '${EMAIL}',
    firstname: '${EMPRESA}',
    lastname: 'Admin',
    email: '${EMAIL}',
    password: '$(openssl rand -base64 12)',
    roles: Role.where(name: 'Administrator'),
    active: true
  )
  Setting.set('organization_logo', 'logo.svg')
  Setting.set('product_name', 'Stratechna Desk')
  Setting.set('organization_name', '${EMPRESA}')
" 2>/dev/null || echo "  ⚠ Configuração inicial via rails — verificar manualmente"

# ── Guardar sumário ───────────────────────────────────────────────────────────
cat > "${INSTANCE_DIR}/INFO.txt" << INFO
Stratechna Desk — ${EMPRESA}
Slug:        ${SLUG}
URL:         https://${SLUG}.desk.stratechna.com
${DOMINIO_PROPRIO:+URL própria: https://${DOMINIO_PROPRIO}}
Admin email: ${EMAIL}
Criado:      $(date '+%Y-%m-%d %H:%M')
INFO

echo ""
echo "✅ Stratechna Desk — instância '${SLUG}' criada com sucesso!"
echo "   URL: https://${SLUG}.desk.stratechna.com"
echo "   Admin: ${EMAIL}"
echo "   Info: ${INSTANCE_DIR}/INFO.txt"
