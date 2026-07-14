#!/usr/bin/env bash
set -Eeuo pipefail

STACK=/opt/docker/stacks/3x-ui
CONFIG=/opt/docker/configs/3x-ui
DATA=/opt/docker/data/3x-ui
LOG=/opt/docker/logs/3x-ui
BACKUP=/opt/docker/backups/3x-ui
ENV_FILE="$CONFIG/.env"
SECRET_FILE="$CONFIG/admin.env"
AUDIT_LOG="$LOG/deploy.log"

[[ ${EUID} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
install -d -m 0750 "$STACK" "$CONFIG" "$DATA" "$LOG" "$BACKUP"
exec > >(tee -a "$AUDIT_LOG") 2>&1

pick_port() {
  local port
  while :; do
    port=$(shuf -i 20000-59999 -n 1)
    ss -ltn "sport = :$port" | grep -q LISTEN || { printf '%s' "$port"; return; }
  done
}

if [[ ! -s "$ENV_FILE" ]]; then
  panel_port=2053
  vless_port=$(pick_port)
  umask 077
  cat > "$ENV_FILE" <<EOF
PANEL_PORT=$panel_port
VLESS_PORT=$vless_port
EOF
  cat > "$SECRET_FILE" <<EOF
PANEL_USER=admin-$(openssl rand -hex 4)
PANEL_PASSWORD=$(openssl rand -base64 36 | tr -d '\n' | tr '/+' '_-')
PANEL_PATH=/$(openssl rand -hex 16)
VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
EOF
  chmod 0600 "$ENV_FILE" "$SECRET_FILE"
fi

if [[ -f "$STACK/compose.yml" ]] && ! cmp -s /tmp/3x-ui.compose.yml "$STACK/compose.yml"; then
  cp -a "$STACK/compose.yml" "$BACKUP/compose.yml.$(date -u +%Y%m%dT%H%M%SZ)"
fi
install -m 0640 /tmp/3x-ui.compose.yml "$STACK/compose.yml"
docker compose --env-file "$ENV_FILE" -f "$STACK/compose.yml" up -d

source "$SECRET_FILE"
for _ in $(seq 1 30); do
  docker exec 3x-ui /app/x-ui setting -show true >/dev/null 2>&1 && break
  sleep 1
done
docker exec 3x-ui /app/x-ui setting -username "$PANEL_USER" -password "$PANEL_PASSWORD" -webBasePath "$PANEL_PATH" -resetTwoFactor=true
docker compose --env-file "$ENV_FILE" -f "$STACK/compose.yml" restart
source "$ENV_FILE"
ufw allow "$VLESS_PORT/tcp" comment '3x-ui VLESS TCP'
printf 'panel_port=%s\nvless_port=%s\n' "$PANEL_PORT" "$VLESS_PORT"
