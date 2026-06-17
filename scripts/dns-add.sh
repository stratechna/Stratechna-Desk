#!/bin/bash
# /opt/stratechna/desk/scripts/dns-add.sh
# Regista subdomínio no PowerDNS (mesmo padrão do Sign e Docs)
# Uso: bash dns-add.sh <nome-relativo> <fqdn>

SUBDOMAIN="$1"   # ex: esferancora.desk
FQDN="$2"        # ex: esferancora.desk.stratechna.com
IP="95.217.8.239"
DOMAIN="stratechna.com"
PDNS_DB="/var/lib/powerdns/pdns.sqlite3"

if [ -z "$SUBDOMAIN" ]; then
  echo "Uso: $0 <subdomain> <fqdn>"
  exit 1
fi

# Obter domain_id
DOMAIN_ID=$(sqlite3 "$PDNS_DB" "SELECT id FROM domains WHERE name='${DOMAIN}' LIMIT 1;")
if [ -z "$DOMAIN_ID" ]; then
  echo "ERRO: domínio ${DOMAIN} não encontrado no PowerDNS"
  exit 1
fi

# Inserir registo A
sqlite3 "$PDNS_DB" "
  INSERT OR REPLACE INTO records (domain_id, name, type, content, ttl, prio)
  VALUES (${DOMAIN_ID}, '${FQDN}.', 'A', '${IP}', 300, 0);
"

# Recarregar PowerDNS
pdns_control reload 2>/dev/null || true

echo "  DNS: ${FQDN} → ${IP} (registado)"
