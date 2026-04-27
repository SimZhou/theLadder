#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

PROJECT_NAME="theLadder"
INSTALL_ROOT="/opt/theladder"
CONFIG_ROOT="/etc/theladder"
BIN_ROOT="/usr/local/bin"
SYSTEMD_ROOT="/etc/systemd/system"

log_info() {
  echo -e "[${green}INFO${plain}] $*"
}

log_warn() {
  echo -e "[${yellow}WARN${plain}] $*"
}

log_error() {
  echo -e "[${red}ERROR${plain}] $*" >&2
}

die() {
  log_error "$*"
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "This command must run as root. Use sudo."
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID,,}"
    OS_LIKE="${ID_LIKE:-}"
  elif [[ -f /etc/redhat-release ]]; then
    OS_ID="centos"
    OS_LIKE="rhel fedora"
  else
    die "Unsupported Linux distribution: /etc/os-release not found."
  fi

  case "${OS_ID} ${OS_LIKE}" in
    *debian*|*ubuntu*)
      PKG_MANAGER="apt"
      ;;
    *rhel*|*fedora*|*centos*|*rocky*|*alma*)
      if command_exists dnf; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      ;;
    *)
      die "Unsupported Linux distribution: ${OS_ID}."
      ;;
  esac
}

install_packages() {
  detect_os
  case "${PKG_MANAGER}" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    yum)
      yum install -y "$@"
      ;;
  esac
}

ensure_base_tools() {
  local missing=()
  for tool in curl tar unzip openssl; do
    command_exists "${tool}" || missing+=("${tool}")
  done
  if ((${#missing[@]} > 0)); then
    install_packages "${missing[@]}"
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      ;;
    armv7l|armv7)
      ARCH="armv7"
      ;;
    *)
      die "Unsupported architecture: $(uname -m)."
      ;;
  esac
}

latest_github_release_tag() {
  local repo="$1"
  local tag=""
  tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1 || true)"
  if [[ -z "${tag}" ]]; then
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" \
      | sed 's|.*/releases/tag/||')"
  fi
  echo "${tag}"
}

github_release_tag_path() {
  local tag="$1"
  echo "${tag//\//%2F}"
}

download_file() {
  local url="$1"
  local output="$2"
  log_info "Downloading ${url}"
  curl -fL --retry 3 --connect-timeout 20 -o "${output}" "${url}"
}

random_uuid() {
  if command_exists uuidgen; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

random_hex() {
  local bytes="${1:-8}"
  openssl rand -hex "${bytes}"
}

random_password() {
  openssl rand -base64 24 | tr -d '\n'
}

public_ip() {
  local ip=""
  ip="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "${ip}" ]]; then
    ip="$(curl -fsS --max-time 3 https://ipv4.icanhazip.com 2>/dev/null | tr -d '\n' || true)"
  fi
  echo "${ip}"
}

open_firewall_port() {
  local port="$1"
  local proto="$2"

  if command_exists firewall-cmd && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${port}/${proto}"
    firewall-cmd --reload
    return
  fi

  if command_exists ufw && ufw status | grep -q "Status: active"; then
    ufw allow "${port}/${proto}"
    return
  fi

  log_warn "No active firewalld/ufw detected. Ensure ${proto} port ${port} is reachable."
}

write_systemd_service() {
  local service_name="$1"
  local exec_start="$2"
  local description="$3"
  local unit_file="${SYSTEMD_ROOT}/${service_name}.service"

  cat >"${unit_file}" <<EOF
[Unit]
Description=${description}
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=${exec_start}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${service_name}"
}

restart_service() {
  local service_name="$1"
  systemctl restart "${service_name}"
  systemctl --no-pager --full status "${service_name}" || true
  systemctl is-active --quiet "${service_name}" || die "Service ${service_name} is not active after restart."
}

stop_disable_service() {
  local service_name="$1"
  if systemctl list-unit-files | grep -q "^${service_name}.service"; then
    systemctl stop "${service_name}" 2>/dev/null || true
    systemctl disable "${service_name}" 2>/dev/null || true
    rm -f "${SYSTEMD_ROOT}/${service_name}.service"
    systemctl daemon-reload
  fi
}

ensure_layout() {
  mkdir -p "${INSTALL_ROOT}" "${CONFIG_ROOT}"
}
