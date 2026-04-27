#!/usr/bin/env bash

legacy_patterns='ssr|shadowsocks|ssserver|server.py|shadowsocksr'

purge_legacy() {
  require_root

  local backup_dir="/root/backup-theLadder-legacy-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${backup_dir}"

  log_info "Backing up legacy files to ${backup_dir}"
  backup_path "/etc/shadowsocks.json" "${backup_dir}"
  backup_path "/etc/shadowsocks-r" "${backup_dir}"
  backup_path "/usr/local/shadowsocks" "${backup_dir}"
  backup_path "/etc/init.d/shadowsocks" "${backup_dir}"
  backup_path "/etc/init.d/ss-fly" "${backup_dir}"
  backup_path "/var/log/shadowsocks.log" "${backup_dir}"

  log_info "Stopping legacy processes"
  stop_legacy_processes

  log_info "Disabling legacy startup entries"
  disable_legacy_init "shadowsocks"
  disable_legacy_init "ss-fly"
  disable_legacy_systemd "shadowsocks"
  disable_legacy_systemd "shadowsocksr"
  disable_legacy_systemd "ssserver"
  disable_legacy_systemd "ss-fly"

  log_info "Removing legacy files"
  rm -f /etc/shadowsocks.json
  rm -rf /etc/shadowsocks-r
  rm -rf /usr/local/shadowsocks
  rm -f /etc/init.d/shadowsocks
  rm -f /etc/init.d/ss-fly
  rm -f /var/run/shadowsocks.pid
  rm -f /var/log/shadowsocks.log

  systemctl daemon-reload 2>/dev/null || true
  systemctl reset-failed 2>/dev/null || true

  log_info "Legacy cleanup complete."
  log_info "Backup directory: ${backup_dir}"

  if pgrep -af "${legacy_patterns}" >/dev/null 2>&1; then
    log_warn "Some matching processes still exist:"
    pgrep -af "${legacy_patterns}" || true
  fi
}

backup_path() {
  local src="$1"
  local backup_dir="$2"
  if [[ -e "${src}" ]]; then
    cp -a "${src}" "${backup_dir}/"
  fi
}

stop_legacy_processes() {
  if [[ -f /usr/local/shadowsocks/server.py && -f /etc/shadowsocks.json ]]; then
    python /usr/local/shadowsocks/server.py -c /etc/shadowsocks.json -d stop 2>/dev/null || true
    python2 /usr/local/shadowsocks/server.py -c /etc/shadowsocks.json -d stop 2>/dev/null || true
    python3 /usr/local/shadowsocks/server.py -c /etc/shadowsocks.json -d stop 2>/dev/null || true
  fi

  pkill -f '/usr/local/shadowsocks/server.py' 2>/dev/null || true
  pkill -f 'ssserver' 2>/dev/null || true
  pkill -f 'shadowsocksr' 2>/dev/null || true
}

disable_legacy_init() {
  local name="$1"
  if [[ -e "/etc/init.d/${name}" ]]; then
    update-rc.d -f "${name}" remove 2>/dev/null || true
    chkconfig --del "${name}" 2>/dev/null || true
  fi
}

disable_legacy_systemd() {
  local name="$1"
  if systemctl list-unit-files 2>/dev/null | grep -q "^${name}.service"; then
    systemctl stop "${name}" 2>/dev/null || true
    systemctl disable "${name}" 2>/dev/null || true
  fi
  rm -f "${SYSTEMD_ROOT}/${name}.service"
}

status_legacy() {
  echo "Processes:"
  pgrep -af "${legacy_patterns}" || true
  echo
  echo "Files:"
  ls -ld \
    /etc/shadowsocks.json \
    /etc/shadowsocks-r \
    /usr/local/shadowsocks \
    /etc/init.d/shadowsocks \
    /etc/init.d/ss-fly \
    2>/dev/null || true
  echo
  echo "Systemd units:"
  systemctl list-unit-files 2>/dev/null | grep -Ei 'ssr|shadowsocks|ss-server|shadowsocksr|ss-fly' || true
}
