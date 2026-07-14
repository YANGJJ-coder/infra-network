#!/usr/bin/env bash
# BandwagonHost Ubuntu 24.04 基础服务器初始化（可重复执行）
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
HOSTNAME_TARGET="bwg-usca6-01"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "请以 root 运行此脚本。" >&2
    exit 1
  fi
}

set_sysctl_value() {
  local key="$1" value="$2" file="/etc/sysctl.conf"
  sed -i -E "\\|^[[:space:]]*${key//./\\.}[[:space:]]*=|d" "$file"
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

require_root

apt-get update
apt-get upgrade -y
apt-get autoremove -y
apt-get install -y \
  curl wget git vim nano jq unzip zip htop btop tree screen tmux net-tools \
  dnsutils software-properties-common ca-certificates gnupg lsb-release \
  fail2ban ufw unattended-upgrades apt-listchanges systemd-timesyncd

timedatectl set-timezone Asia/Shanghai
timedatectl set-ntp true
systemctl enable --now systemd-timesyncd

old_hostname="$(hostname)"
hostnamectl set-hostname "$HOSTNAME_TARGET"
if grep -qE '^[[:space:]]*127\.0\.1\.1[[:space:]]+' /etc/hosts; then
  sed -i -E "s/^(127\.0\.1\.1[[:space:]]+).*/\\1${HOSTNAME_TARGET}/" /etc/hosts
else
  printf '127.0.1.1\t%s\n' "$HOSTNAME_TARGET" >> /etc/hosts
fi
if [[ "$old_hostname" != "$HOSTNAME_TARGET" ]]; then
  sed -i "s/\\b${old_hostname//./\\.}\\b/${HOSTNAME_TARGET}/g" /etc/hosts
fi

install -d -m 0755 /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable

set_sysctl_value net.core.default_qdisc fq
set_sysctl_value net.ipv4.tcp_congestion_control bbr
set_sysctl_value net.ipv4.ip_forward 1
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr
sysctl -w net.ipv4.ip_forward=1

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
. /etc/os-release
arch="$(dpkg --print-architecture)"
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' \
  "$arch" "$VERSION_CODENAME" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
install -d -m 0755 /opt/docker

install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-bwg-limits.conf <<'EOF'
[Journal]
SystemMaxUse=200M
SystemKeepFree=500M
RuntimeMaxUse=100M
MaxRetentionSec=30day
Compress=yes
EOF
systemctl restart systemd-journald

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat > /etc/apt/apt.conf.d/52bwg-unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
        "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer

echo "基础服务器初始化配置已应用。"
