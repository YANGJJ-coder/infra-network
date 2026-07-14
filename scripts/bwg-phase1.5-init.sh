#!/usr/bin/env bash
# BandwagonHost Phase 1.5: long-term operations baseline, no proxy components.
set -Eeuo pipefail

LOG_FILE=/var/log/bwg-phase1.5.log
BACKUP_ROOT=/var/backups/bwg-phase1.5
KEY_STORE=/usr/local/share/bwg-phase1.5-admin.pub
MODE=prepare
KEY_FILE=

usage() {
  echo "Usage: $0 --key-file /path/to/id_ed25519.pub [--harden-ssh]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key-file) KEY_FILE=${2:?}; shift 2 ;;
    --harden-ssh) MODE=harden; shift ;;
    *) usage; exit 2 ;;
  esac
done

[[ ${EUID} -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ -n "$KEY_FILE" && -s "$KEY_FILE" ]] || { usage >&2; exit 2; }

mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_ROOT"
exec > >(tee -a "$LOG_FILE") 2>&1
umask 022
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="$BACKUP_ROOT/$RUN_ID"
mkdir -p "$BACKUP_DIR/files" "$BACKUP_DIR/missing"

backup_file() {
  local path="$1" safe="${1#/}"
  [[ -e "$BACKUP_DIR/files/$safe" || -e "$BACKUP_DIR/missing/$safe" ]] && return
  if [[ -e "$path" ]]; then
    install -d -m 0700 "$(dirname "$BACKUP_DIR/files/$safe")"
    cp -a "$path" "$BACKUP_DIR/files/$safe"
  else
    install -d -m 0700 "$(dirname "$BACKUP_DIR/missing/$safe")"
    : > "$BACKUP_DIR/missing/$safe"
  fi
}

write_restore_script() {
  cat > "$BACKUP_DIR/restore.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
base="$BACKUP_DIR"
for path in /etc/ssh/sshd_config.d/99-bwg-phase1.5.conf /etc/docker/daemon.json /etc/profile.d/99-bwg-ops.sh /root/.bashrc /home/yjj/.bashrc /root/.ssh/authorized_keys /home/yjj/.ssh/authorized_keys; do
  safe="\${path#/}"
  if [[ -e "\$base/files/\$safe" ]]; then
    install -d -m 0755 "\$(dirname "\$path")"
    cp -a "\$base/files/\$safe" "\$path"
  elif [[ -e "\$base/missing/\$safe" ]]; then
    rm -f "\$path"
  fi
done
sshd -t
systemctl reload ssh
systemctl restart docker
echo "Restored backup: \$base"
EOF
  chmod 0700 "$BACKUP_DIR/restore.sh"
}

append_key() {
  local account="$1" home keyfile
  home=$(getent passwd "$account" | cut -d: -f6)
  keyfile="$home/.ssh/authorized_keys"
  if [[ -f "$keyfile" ]] && grep -qxF "$(cat "$KEY_STORE")" "$keyfile"; then
    return
  fi
  backup_file "$keyfile"
  install -d -m 0700 -o "$account" -g "$account" "$home/.ssh"
  touch "$keyfile"
  chown "$account:$account" "$keyfile"
  chmod 0600 "$keyfile"
  cat "$KEY_STORE" >> "$keyfile"
}

ensure_bashrc_source() {
  local path="$1" line='source /etc/profile.d/99-bwg-ops.sh'
  if [[ ! -f "$path" ]] || ! grep -qxF "$line" "$path"; then
    backup_file "$path"
    touch "$path"
    printf '\n# BandwagonHost Phase 1.5 operations baseline\n%s\n' "$line" >> "$path"
  fi
}

ensure_admin() {
  if ! id yjj >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --groups sudo,docker,adm,systemd-journal yjj
  else
    usermod -aG sudo,docker,adm,systemd-journal yjj
  fi
  install -d -m 0755 /usr/local/share
  if [[ ! -f "$KEY_STORE" ]] || ! cmp -s "$KEY_FILE" "$KEY_STORE"; then
    cp "$KEY_FILE" "$KEY_STORE"
    chmod 0644 "$KEY_STORE"
  fi
  append_key root
  append_key yjj
}

ensure_directories() {
  install -d -m 0755 /opt/docker/{compose,stacks,configs,backups,logs,monitoring,scripts,data}
  install -d -m 0755 /opt/{backup,scripts,logs,temp}
}

ensure_docker_config() {
  local tmp changed=0
  tmp=$(mktemp)
  python3 - /etc/docker/daemon.json "$tmp" <<'PY'
import json, pathlib, sys
source, target = map(pathlib.Path, sys.argv[1:])
data = json.loads(source.read_text()) if source.exists() else {}
if not isinstance(data, dict):
    raise SystemExit('/etc/docker/daemon.json must contain a JSON object')
opts = data.setdefault('log-opts', {})
if not isinstance(opts, dict):
    raise SystemExit('Docker log-opts must contain a JSON object')
data['log-driver'] = 'json-file'
opts['max-size'] = '10m'
opts['max-file'] = '3'
target.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
PY
  python3 -m json.tool "$tmp" >/dev/null
  if [[ ! -f /etc/docker/daemon.json ]] || ! cmp -s "$tmp" /etc/docker/daemon.json; then
    backup_file /etc/docker/daemon.json
    install -d -m 0755 /etc/docker
    install -m 0644 "$tmp" /etc/docker/daemon.json
    changed=1
  fi
  rm -f "$tmp"
  systemctl enable docker containerd
  if (( changed )); then
    systemctl restart docker
  else
    systemctl start docker
  fi
}

ensure_ops_shell() {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
# BandwagonHost Phase 1.5 operations baseline
[[ $- == *i* ]] || return 0
HISTSIZE=50000
HISTFILESIZE=100000
HISTTIMEFORMAT='%F %T '
shopt -s histappend
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
alias ll='ls -alF'
alias la='ls -A'
alias cls='clear'
alias update='sudo apt update && sudo apt upgrade && sudo apt autoremove'
alias upgrade='sudo apt upgrade'
alias ports='sudo ss -tulpn'
alias dockerps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias dockerlogs='docker logs --tail 200 -f'
alias dockerstats='docker stats'
alias fd='fdfind'
if [[ -r /usr/share/bash-completion/bash_completion ]]; then
  source /usr/share/bash-completion/bash_completion
fi
EOF
  if [[ ! -f /etc/profile.d/99-bwg-ops.sh ]] || ! cmp -s "$tmp" /etc/profile.d/99-bwg-ops.sh; then
    backup_file /etc/profile.d/99-bwg-ops.sh
    install -m 0644 "$tmp" /etc/profile.d/99-bwg-ops.sh
  fi
  rm -f "$tmp"
  ensure_bashrc_source /root/.bashrc
  ensure_bashrc_source /home/yjj/.bashrc
  chown yjj:yjj /home/yjj/.bashrc
}

ensure_tools() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y vnstat iotop ncdu iftop lsof ripgrep fd-find bash-completion
  systemctl enable --now vnstat
}

harden_ssh() {
  local tmp
  grep -qxF "$(cat "$KEY_STORE")" /root/.ssh/authorized_keys
  grep -qxF "$(cat "$KEY_STORE")" /home/yjj/.ssh/authorized_keys
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
ClientAliveInterval 300
ClientAliveCountMax 3
EOF
  if [[ ! -f /etc/ssh/sshd_config.d/99-bwg-phase1.5.conf ]] || ! cmp -s "$tmp" /etc/ssh/sshd_config.d/99-bwg-phase1.5.conf; then
    backup_file /etc/ssh/sshd_config.d/99-bwg-phase1.5.conf
    install -d -m 0755 /etc/ssh/sshd_config.d
    install -m 0644 "$tmp" /etc/ssh/sshd_config.d/99-bwg-phase1.5.conf
  fi
  rm -f "$tmp"
  sshd -t
  systemctl reload ssh
}

ensure_admin
ensure_directories
ensure_docker_config
ensure_tools
ensure_ops_shell
write_restore_script

if [[ "$MODE" == harden ]]; then
  harden_ssh
fi

echo "Phase 1.5 mode=$MODE completed. Backup: $BACKUP_DIR"
