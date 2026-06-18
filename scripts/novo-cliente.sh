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
LOGO_SVG="/opt/stratechna/desk/branding/logo.svg"

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
SECRET=$(openssl rand -hex 32)
DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

# ── Criar directório da instância ──────────────────────────────────────────────
mkdir -p "${INSTANCE_DIR}"

# ── Gerar .env ─────────────────────────────────────────────────────────────────
cat > "${INSTANCE_DIR}/.env" << ENV
SLUG=${SLUG}
EMAIL=${EMAIL}
EMPRESA=${EMPRESA}
SECRET=${SECRET}
DB_PASS=${DB_PASS}
ENV

# ── Regra domínio próprio para Traefik ────────────────────────────────────────
if [ -n "$DOMINIO_PROPRIO" ]; then
  EXTRA_HOSTS=" || Host(\`${DOMINIO_PROPRIO}\`)"
else
  EXTRA_HOSTS=""
fi

# ── Gerar docker-compose.yml ───────────────────────────────────────────────────
cat > "${INSTANCE_DIR}/docker-compose.yml" << COMPOSE
x-shared:
  zammad-service: &zammad-service
    image: ghcr.io/stratechna/stratechna-desk:latest
    restart: unless-stopped
    environment: &zammad-environment
      POSTGRESQL_DB: desk_${SLUG}
      POSTGRESQL_HOST: desk-${SLUG}-db
      POSTGRESQL_USER: desk_${SLUG}
      POSTGRESQL_PASS: ${DB_PASS}
      POSTGRESQL_PORT: 5432
      REDIS_URL: redis://desk-${SLUG}-redis:6379
      MEMCACHE_SERVERS: desk-${SLUG}-memcached:11211
      ELASTICSEARCH_HOST: desk-${SLUG}-es
      ELASTICSEARCH_PORT: 9200
      ZAMMAD_FQDN: ${SLUG}.desk.stratechna.com
      ZAMMAD_HTTP_TYPE: https
      NGINX_SERVER_SCHEME: https
      RAILS_TRUSTED_PROXIES: "['127.0.0.1', '::1', 'desk-${SLUG}-nginx']"
      ZAMMAD_RAILSSERVER_HOST: desk-${SLUG}-railsserver
      ZAMMAD_WEBSOCKET_HOST: desk-${SLUG}-websocket
      TZ: Europe/Lisbon
    volumes:
      - desk-${SLUG}-storage:/opt/zammad/storage
    depends_on:
      desk-${SLUG}-db:
        condition: service_healthy
      desk-${SLUG}-redis:
        condition: service_healthy
      desk-${SLUG}-memcached:
        condition: service_healthy

services:

  desk-${SLUG}-init:
    <<: *zammad-service
    container_name: desk-${SLUG}-init
    command: ["zammad-init"]
    depends_on:
      desk-${SLUG}-db:
        condition: service_healthy
    restart: on-failure
    user: 0:0
    volumes:
      - desk-${SLUG}-storage:/opt/zammad/storage
      - desk-${SLUG}-backup:/var/tmp/zammad
    networks:
      - desk-${SLUG}-internal

  desk-${SLUG}-railsserver:
    <<: *zammad-service
    container_name: desk-${SLUG}-railsserver
    command: ["zammad-railsserver"]
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://127.0.0.1:3000"]
      interval: 30s
      timeout: 5s
      start_period: 120s
      retries: 3
    networks:
      desk-${SLUG}-internal:
        aliases:
          - zammad-railsserver

  desk-${SLUG}-websocket:
    <<: *zammad-service
    container_name: desk-${SLUG}-websocket
    command: ["zammad-websocket"]
    networks:
      desk-${SLUG}-internal:
        aliases:
          - zammad-websocket

  desk-${SLUG}-scheduler:
    <<: *zammad-service
    container_name: desk-${SLUG}-scheduler
    command: ["zammad-scheduler"]
    networks:
      - desk-${SLUG}-internal

  desk-${SLUG}-nginx:
    <<: *zammad-service
    container_name: desk-${SLUG}-nginx
    command: ["zammad-nginx"]
    depends_on:
      desk-${SLUG}-railsserver:
        condition: service_healthy
    networks:
      - proxy
      - desk-${SLUG}-internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.desk-${SLUG}.rule=Host(\`${SLUG}.desk.stratechna.com\`)${EXTRA_HOSTS}"
      - "traefik.http.routers.desk-${SLUG}.entrypoints=websecure"
      - "traefik.http.routers.desk-${SLUG}.tls.certresolver=letsencrypt"
      - "traefik.http.services.desk-${SLUG}.loadbalancer.server.port=8080"

  desk-${SLUG}-db:
    image: postgres:17-alpine
    container_name: desk-${SLUG}-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: desk_${SLUG}
      POSTGRES_USER: desk_${SLUG}
      POSTGRES_PASSWORD: ${DB_PASS}
    volumes:
      - desk-${SLUG}-db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U desk_${SLUG} -d desk_${SLUG}"]
      interval: 10s
      timeout: 5s
      start_period: 60s
      retries: 5
    networks:
      - desk-${SLUG}-internal

  desk-${SLUG}-redis:
    image: redis:8-alpine
    container_name: desk-${SLUG}-redis
    restart: unless-stopped
    volumes:
      - desk-${SLUG}-redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - desk-${SLUG}-internal

  desk-${SLUG}-memcached:
    image: memcached:1.6-alpine
    container_name: desk-${SLUG}-memcached
    command: memcached -m 256M
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "11211"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - desk-${SLUG}-internal

  desk-${SLUG}-es:
    image: elasticsearch:8.13.0
    container_name: desk-${SLUG}-es
    restart: unless-stopped
    environment:
      discovery.type: single-node
      xpack.security.enabled: "false"
      ES_JAVA_OPTS: -Xms512m -Xmx512m
    volumes:
      - desk-${SLUG}-es:/usr/share/elasticsearch/data
    networks:
      - desk-${SLUG}-internal

volumes:
  desk-${SLUG}-storage:
  desk-${SLUG}-backup:
  desk-${SLUG}-db:
  desk-${SLUG}-redis:
  desk-${SLUG}-es:

networks:
  proxy:
    external: true
  desk-${SLUG}-internal:
    name: desk-${SLUG}-internal
COMPOSE

# ── DNS via PowerDNS ──────────────────────────────────────────────────────────
echo "▶ A registar DNS: ${SLUG}.desk.stratechna.com → 95.217.8.239"
bash "${SCRIPTS_DIR}/dns-add.sh" "${SLUG}.desk" "${SLUG}.desk.stratechna.com"

# ── Arrancar containers ───────────────────────────────────────────────────────
echo "▶ A arrancar containers..."
cd "${INSTANCE_DIR}"
docker compose pull
docker compose up -d

# ── Aguardar railsserver estar pronto ─────────────────────────────────────────
echo "▶ A aguardar inicialização (pode demorar 2-3 minutos)..."
RETRIES=20
for i in $(seq 1 $RETRIES); do
  STATUS=$(docker exec desk-${SLUG}-railsserver curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "301" ] || [ "$STATUS" = "302" ]; then
    echo "✓ Zammad pronto."
    break
  fi
  echo "  ... aguardar (tentativa ${i}/${RETRIES})"
  sleep 15
done

# ── Configuração inicial via Rails ────────────────────────────────────────────
echo "▶ A configurar branding..."

# Logo em base64
if [ -f "$LOGO_SVG" ]; then
  B64=$(base64 -w 0 "$LOGO_SVG")
  cat > /tmp/desk_setup_${SLUG}.rb << RUBY
Setting.set('product_name', 'Stratechna Desk')
Setting.set('product_logo', 'data:image/svg+xml;base64,${B64}')
puts 'branding ok'
RUBY
  docker cp /tmp/desk_setup_${SLUG}.rb desk-${SLUG}-railsserver:/tmp/desk_setup.rb
  docker exec desk-${SLUG}-railsserver bundle exec rails r /tmp/desk_setup.rb 2>/dev/null | grep -v "^I,\|^W," || true
  rm /tmp/desk_setup_${SLUG}.rb
fi

# ── Guardar sumário ───────────────────────────────────────────────────────────
cat > "${INSTANCE_DIR}/INFO.txt" << INFO
Stratechna Desk — ${EMPRESA}
Slug:        ${SLUG}
URL:         https://${SLUG}.desk.stratechna.com
${DOMINIO_PROPRIO:+URL própria: https://${DOMINIO_PROPRIO}}
Admin email: ${EMAIL}
DB Pass:     ${DB_PASS}
Criado:      $(date '+%Y-%m-%d %H:%M')
INFO

echo ""
echo "✅ Stratechna Desk — instância '${SLUG}' criada!"
echo "   URL: https://${SLUG}.desk.stratechna.com"
echo "   Completa o setup em: https://${SLUG}.desk.stratechna.com/#getting_started"
echo "   Info: ${INSTANCE_DIR}/INFO.txt"
