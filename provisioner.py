"""
app/services/provisioner.py
Provisioning automático de instâncias Docker via scripts existentes.

Delega inteiramente no script bash novo-cliente.sh — não reimplementa
lógica Docker. Usa asyncio.run_in_executor para não bloquear o event loop.

Scripts usados (existem no servidor):
  /opt/stratechna/docs/scripts/novo-cliente.sh   <slug> <email>
  /opt/stratechna/docs/scripts/remover-cliente.sh <slug>
  /opt/stratechna/sign/scripts/novo-cliente.sh   <slug> <email>
  /opt/stratechna/sign/scripts/remover-cliente.sh <slug>
  /opt/stratechna/desk/scripts/novo-cliente.sh   <slug> <email>
  /opt/stratechna/desk/scripts/remover-cliente.sh <slug>
  /opt/stratechna/crm/scripts/novo-cliente.sh    <slug> <email>
  /opt/stratechna/crm/scripts/remover-cliente.sh <slug>

Containers suspensos/reactivados via `docker compose stop/start` directamente.
"""

import asyncio
import logging
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from sqlalchemy.orm import Session

from app.models import AppDefinition, AppInstance, EventAction, InstanceStatus
from app.models import Client
from app.services.logger import log_event

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuração de apps — mapa slug → paths
# ---------------------------------------------------------------------------

APPS = {
    "docs": {
        "scripts_dir": Path("/opt/stratechna/docs/scripts"),
        "clients_dir": Path("/opt/stratechna/docs/clientes"),
    },
    "vault": {  # alias legacy → docs
        "scripts_dir": Path("/opt/stratechna/docs/scripts"),
        "clients_dir": Path("/opt/stratechna/docs/clientes"),
    },
    "sign": {
        "scripts_dir": Path("/opt/stratechna/sign/scripts"),
        "clients_dir": Path("/opt/stratechna/sign/clientes"),
    },
    "desk": {
        "scripts_dir": Path("/opt/stratechna/desk/scripts"),
        "clients_dir": Path("/opt/stratechna/desk/clientes"),
    },
    "crm": {
        "scripts_dir": Path("/opt/stratechna/crm/scripts"),
        "clients_dir": Path("/opt/stratechna/crm/clientes"),
    },
}

SCRIPT_TIMEOUT = 300  # segundos — docker pull pode demorar


def _app_config(app_slug: str) -> dict:
    """Devolve config da app, com fallback para docs se slug desconhecido."""
    return APPS.get(app_slug, APPS["docs"])


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------

def _run_sync(cmd: list[str], timeout: int = SCRIPT_TIMEOUT) -> subprocess.CompletedProcess:
    """Corre um comando síncrono com timeout, sem heredar variáveis de terminal."""
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, "TERM": "dumb", "DEBIAN_FRONTEND": "noninteractive"},
    )


async def _run_async(cmd: list[str], timeout: int = SCRIPT_TIMEOUT) -> subprocess.CompletedProcess:
    """Wrapper assíncrono sobre _run_sync — não bloqueia o event loop."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, lambda: _run_sync(cmd, timeout))


def _instance_dir_exists(slug: str, app_slug: str) -> bool:
    return (_app_config(app_slug)["clients_dir"] / slug).exists()


def _compose_file(slug: str, app_slug: str) -> Path:
    return _app_config(app_slug)["clients_dir"] / slug / "docker-compose.yml"


# ---------------------------------------------------------------------------
# Criar instância completa (ligado ao POST /clients)
# ---------------------------------------------------------------------------

async def provision_client(
    db: Session,
    client: Client,
    admin_email: str,
    app_slug: str = "docs",
    source: str = "manual",
) -> dict:
    """
    Provisiona todos os containers para um cliente novo.

    Chama novo-cliente.sh <slug> <email> de forma assíncrona.
    O script faz: validação, geração de secrets, docker-compose, docker pull+up,
    registo DNS e em clientes.log.

    Returns:
        {
            "success": bool,
            "message": str,
            "instance_url": str | None,
            "stdout": str,
            "stderr": str,
        }
    """
    slug = client.slug
    cfg = _app_config(app_slug)
    script_novo = cfg["scripts_dir"] / "novo-cliente.sh"

    # Verificar se já existe (idempotência)
    if _instance_dir_exists(slug, app_slug):
        msg = f"Instância '{slug}' ({app_slug}) já existe — provisioning ignorado."
        logger.warning(f"[provisioner] {msg}")
        log_event(db, EventAction.created,
                  f"Provisioning ignorado: instância '{slug}' já existe",
                  client_id=client.id, source=source)
        db.commit()
        return {"success": False, "message": msg,
                "instance_url": None, "stdout": "", "stderr": ""}

    if not script_novo.exists():
        msg = f"Script não encontrado: {script_novo}"
        logger.error(f"[provisioner] {msg}")
        log_event(db, EventAction.created,
                  f"Provisioning falhou: script ausente", client_id=client.id, source=source)
        db.commit()
        return {"success": False, "message": msg,
                "instance_url": None, "stdout": "", "stderr": ""}

    logger.info(f"[provisioner] A provisionar '{slug}' app='{app_slug}' ({admin_email})")
    log_event(db, EventAction.created,
              f"Provisioning iniciado para '{slug}' ({app_slug})",
              client_id=client.id, source=source)
    db.commit()

    try:
        result = await _run_async([str(script_novo), slug, admin_email])
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()

        if result.returncode == 0:
            instance_url = _extract_url(stdout, slug, app_slug)
            creds = _extract_credentials(stdout, slug, admin_email, instance_url)
            logger.info(f"[provisioner] '{slug}' ({app_slug}) provisionado → {instance_url}")

            log_event(db, EventAction.app_added,
                      f"Provisioning concluído para '{slug}' ({app_slug}) — {instance_url}",
                      client_id=client.id, source=source)

            await _create_app_instances(db, client, app_slug=app_slug, credentials=creds)
            db.commit()

            return {
                "success": True,
                "message": f"Cliente '{slug}' provisionado com sucesso.",
                "instance_url": instance_url,
                "stdout": stdout,
                "stderr": stderr,
            }
        else:
            msg = f"Script terminou com rc={result.returncode}"
            logger.error(f"[provisioner] Erro em '{slug}': {msg}\n{stderr[:300]}")
            log_event(db, EventAction.created,
                      f"Provisioning falhou: {msg} — {stderr[:200]}",
                      client_id=client.id, source=source)
            db.commit()
            return {"success": False, "message": msg,
                    "instance_url": None, "stdout": stdout, "stderr": stderr}

    except subprocess.TimeoutExpired:
        msg = f"Script excedeu timeout de {SCRIPT_TIMEOUT}s"
        logger.error(f"[provisioner] Timeout em '{slug}'")
        log_event(db, EventAction.created, f"Provisioning timeout: {msg}",
                  client_id=client.id, source=source)
        db.commit()
        return {"success": False, "message": msg,
                "instance_url": None, "stdout": "", "stderr": ""}

    except Exception as exc:
        msg = str(exc)
        logger.exception(f"[provisioner] Excepção em '{slug}'")
        log_event(db, EventAction.created, f"Provisioning erro: {msg[:300]}",
                  client_id=client.id, source=source)
        db.commit()
        return {"success": False, "message": msg,
                "instance_url": None, "stdout": "", "stderr": ""}


def _extract_credentials(stdout: str, slug: str, admin_email: str, instance_url: str) -> dict:
    """Extrai credenciais do output do script novo-cliente.sh."""
    import re
    creds = {
        "url":      instance_url,
        "email":    admin_email,
        "password": None,
    }
    for line in stdout.splitlines():
        line = line.strip()
        m = re.search(r'Pass[:\s]+([A-Za-z0-9_\-]{8,})', line)
        if m:
            creds["password"] = m.group(1)
            break
    return creds


def _extract_url(stdout: str, slug: str, app_slug: str = "docs") -> str:
    """Extrai URL do output do script (linha 'URL: https://...') ou usa convenção."""
    for line in stdout.splitlines():
        stripped = line.strip()
        if stripped.upper().startswith("URL:"):
            url = stripped.split(":", 1)[1].strip()
            if url.startswith("http"):
                return url
    # Convenção por app
    conventions = {
        "docs":   f"https://docs.{slug}.stratechna.com",
        "vault":  f"https://docs.{slug}.stratechna.com",
        "sign":   f"https://{slug}.sign.stratechna.com",
        "desk":   f"https://{slug}.desk.stratechna.com",
        "crm":    f"https://{slug}.crm.stratechna.com",
    }
    return conventions.get(app_slug, f"https://{slug}.{app_slug}.stratechna.com")


async def _create_app_instances(db: Session, client: Client, app_slug: str = "docs", credentials: dict = None) -> None:
    """
    Cria registo AppInstance na BD para a app contratada.
    """
    # Normalizar alias vault → docs
    resolved_slug = "docs" if app_slug == "vault" else app_slug

    app_def = db.query(AppDefinition).filter_by(slug=resolved_slug).first()
    if not app_def:
        logger.warning(f"[provisioner] AppDefinition '{resolved_slug}' não encontrada — a saltar.")
        return

    existing = db.query(AppInstance).filter_by(
        client_id=client.id,
        app_definition_id=app_def.id,
    ).first()
    if existing:
        logger.info(f"[provisioner] AppInstance '{resolved_slug}' já existe para '{client.slug}'.")
        return

    subdomain = _extract_url("", client.slug, resolved_slug).replace("https://", "")
    instance = AppInstance(
        client_id=client.id,
        app_definition_id=app_def.id,
        status=InstanceStatus.active,
        subdomain=subdomain,
        created_at=datetime.now(timezone.utc),
    )
    if credentials:
        instance.credentials = credentials
    db.add(instance)
    logger.info(f"[provisioner] AppInstance '{resolved_slug}' criada: {subdomain}")


# ---------------------------------------------------------------------------
# Suspender containers
# ---------------------------------------------------------------------------

async def suspend_client_containers(
    db: Session,
    client: Client,
    source: str = "manual",
) -> dict:
    """
    Para os containers Docker de um cliente via `docker compose stop`.
    Preserva dados — apenas para os processos.
    Itera sobre todas as AppInstances activas do cliente.
    """
    slug = client.slug
    stopped_any = False
    errors = []

    # Obter slugs das apps activas deste cliente
    active_app_slugs = []
    for inst in client.app_instances:
        if inst.status == InstanceStatus.active and inst.app_definition:
            active_app_slugs.append(inst.app_definition.slug)

    if not active_app_slugs:
        # Fallback: tentar docs (comportamento anterior)
        active_app_slugs = ["docs"]

    for a_slug in active_app_slugs:
        compose = _compose_file(slug, a_slug)
        if not compose.exists():
            logger.warning(f"[provisioner] compose não encontrado para '{slug}' ({a_slug})")
            continue

        try:
            result = await _run_async(
                ["docker", "compose", "-f", str(compose), "stop"],
                timeout=90,
            )
            if result.returncode == 0:
                stopped_any = True
            else:
                errors.append(f"{a_slug}: rc={result.returncode}")
        except Exception as exc:
            errors.append(f"{a_slug}: {str(exc)}")

    if stopped_any or not errors:
        for inst in client.app_instances:
            if inst.status == InstanceStatus.active:
                inst.status = InstanceStatus.suspended
                inst.suspended_at = datetime.now(timezone.utc)
        log_event(db, EventAction.suspended,
                  f"Containers de '{slug}' suspensos",
                  client_id=client.id, source=source)
        db.commit()
        return {"success": True, "message": f"Containers de '{slug}' suspensos."}
    else:
        msg = f"Erros ao suspender: {'; '.join(errors)}"
        log_event(db, EventAction.suspended,
                  f"Suspensão falhou: {msg}", client_id=client.id, source=source)
        db.commit()
        return {"success": False, "message": msg}


# ---------------------------------------------------------------------------
# Reactivar containers
# ---------------------------------------------------------------------------

async def reactivate_client_containers(
    db: Session,
    client: Client,
    source: str = "manual",
) -> dict:
    """
    Inicia os containers Docker de um cliente via `docker compose start`.
    Itera sobre todas as AppInstances suspensas do cliente.
    """
    slug = client.slug
    started_any = False
    errors = []

    suspended_app_slugs = []
    for inst in client.app_instances:
        if inst.status == InstanceStatus.suspended and inst.app_definition:
            suspended_app_slugs.append(inst.app_definition.slug)

    if not suspended_app_slugs:
        suspended_app_slugs = ["docs"]

    for a_slug in suspended_app_slugs:
        compose = _compose_file(slug, a_slug)
        if not compose.exists():
            logger.warning(f"[provisioner] compose não encontrado para '{slug}' ({a_slug})")
            continue

        try:
            result = await _run_async(
                ["docker", "compose", "-f", str(compose), "start"],
                timeout=90,
            )
            if result.returncode == 0:
                started_any = True
            else:
                errors.append(f"{a_slug}: rc={result.returncode}")
        except Exception as exc:
            errors.append(f"{a_slug}: {str(exc)}")

    if started_any or not errors:
        for inst in client.app_instances:
            if inst.status == InstanceStatus.suspended:
                inst.status = InstanceStatus.active
                inst.suspended_at = None
        log_event(db, EventAction.reactivated,
                  f"Containers de '{slug}' reactivados",
                  client_id=client.id, source=source)
        db.commit()
        return {"success": True, "message": f"Containers de '{slug}' reactivados."}
    else:
        msg = f"Erros ao reactivar: {'; '.join(errors)}"
        log_event(db, EventAction.reactivated,
                  f"Reactivação falhou: {msg}", client_id=client.id, source=source)
        db.commit()
        return {"success": False, "message": msg}


# ---------------------------------------------------------------------------
# Remover instância (cancelamento definitivo)
# ---------------------------------------------------------------------------

async def remove_client_instance(
    db: Session,
    client: Client,
    source: str = "manual",
) -> dict:
    """
    Remove completamente as instâncias Docker de um cliente.
    ⚠ Destrutivo — remove volumes e dados do cliente.
    """
    slug = client.slug
    removed_any = False
    errors = []

    all_app_slugs = []
    for inst in client.app_instances:
        if inst.status != InstanceStatus.deleted and inst.app_definition:
            all_app_slugs.append(inst.app_definition.slug)

    if not all_app_slugs:
        all_app_slugs = ["docs"]

    for a_slug in all_app_slugs:
        cfg = _app_config(a_slug)
        script_remover = cfg["scripts_dir"] / "remover-cliente.sh"

        if not script_remover.exists():
            logger.warning(f"[provisioner] remover-cliente.sh não encontrado para {a_slug}")
            errors.append(f"{a_slug}: script ausente")
            continue

        if not _instance_dir_exists(slug, a_slug):
            logger.info(f"[provisioner] Instância '{slug}' ({a_slug}) não existe — saltar.")
            removed_any = True
            continue

        try:
            result = await _run_async([str(script_remover), slug], timeout=120)
            if result.returncode == 0:
                removed_any = True
            else:
                errors.append(f"{a_slug}: rc={result.returncode} {result.stderr[:100]}")
        except Exception as exc:
            errors.append(f"{a_slug}: {str(exc)}")

    if removed_any:
        for inst in client.app_instances:
            inst.status = InstanceStatus.deleted
            inst.deleted_at = datetime.now(timezone.utc)
        log_event(db, EventAction.deleted,
                  f"Instâncias de '{slug}' removidas",
                  client_id=client.id, source=source)
        db.commit()
        return {"success": True, "message": f"Instâncias de '{slug}' removidas."}
    else:
        msg = f"Erros ao remover: {'; '.join(errors)}"
        log_event(db, EventAction.deleted,
                  f"Remoção falhou: {msg}", client_id=client.id, source=source)
        db.commit()
        return {"success": False, "message": msg}
