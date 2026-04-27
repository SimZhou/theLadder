#!/usr/bin/env bash

install_hysteria2() {
  require_root
  ensure_layout
  ensure_base_tools
  detect_arch

  local port="${1:-443}"
  local tag binary_name url tmp_file password obfs_password server_ip

  case "${ARCH}" in
    amd64) binary_name="hysteria-linux-amd64" ;;
    arm64) binary_name="hysteria-linux-arm64" ;;
    armv7) binary_name="hysteria-linux-armv7" ;;
    *) die "Unsupported Hysteria2 architecture: ${ARCH}" ;;
  esac

  tag="$(latest_github_release_tag "apernet/hysteria")"
  [[ -n "${tag}" ]] || die "Unable to resolve latest Hysteria release."

  tmp_file="$(mktemp)"
  url="https://github.com/apernet/hysteria/releases/download/$(github_release_tag_path "${tag}")/${binary_name}"
  download_file "${url}" "${tmp_file}"
  install -m 0755 "${tmp_file}" "${BIN_ROOT}/hysteria"
  rm -f "${tmp_file}"

  password="$(random_password)"
  obfs_password="$(random_password)"

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${CONFIG_ROOT}/hysteria2.key" \
    -out "${CONFIG_ROOT}/hysteria2.crt" \
    -subj "/CN=bing.com" \
    -days 3650 >/dev/null 2>&1

  cat >"${CONFIG_ROOT}/hysteria2.yaml" <<EOF
listen: :${port}

tls:
  cert: ${CONFIG_ROOT}/hysteria2.crt
  key: ${CONFIG_ROOT}/hysteria2.key

auth:
  type: password
  password: ${password}

obfs:
  type: salamander
  salamander:
    password: ${obfs_password}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

  write_systemd_service "theladder-hysteria2" "${BIN_ROOT}/hysteria server -c ${CONFIG_ROOT}/hysteria2.yaml" "theLadder Hysteria2"
  open_firewall_port "${port}" "udp"
  restart_service "theladder-hysteria2"

  server_ip="$(public_ip)"
  [[ -n "${server_ip}" ]] || server_ip="<server-ip>"

  cat >"${CONFIG_ROOT}/hysteria2-client.yaml" <<EOF
server: ${server_ip}:${port}
auth: ${password}

tls:
  sni: bing.com
  insecure: true

obfs:
  type: salamander
  salamander:
    password: ${obfs_password}
EOF

  log_info "Hysteria2 installed: ${tag}"
  echo
  cat "${CONFIG_ROOT}/hysteria2-client.yaml"
}

uninstall_hysteria2() {
  require_root
  stop_disable_service "theladder-hysteria2"
  rm -f \
    "${CONFIG_ROOT}/hysteria2.yaml" \
    "${CONFIG_ROOT}/hysteria2-client.yaml" \
    "${CONFIG_ROOT}/hysteria2.crt" \
    "${CONFIG_ROOT}/hysteria2.key"
  log_info "Hysteria2 removed."
}

status_hysteria2() {
  systemctl --no-pager --full status theladder-hysteria2
}

show_hysteria2() {
  if [[ -f "${CONFIG_ROOT}/hysteria2-client.yaml" ]]; then
    cat "${CONFIG_ROOT}/hysteria2-client.yaml"
  else
    die "Hysteria2 client info not found. Run: $0 install hysteria2"
  fi
}
