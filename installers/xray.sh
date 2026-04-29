#!/usr/bin/env bash

install_xray() {
  require_root
  ensure_layout
  ensure_base_tools
  ensure_bbr
  detect_arch

  local port="${1:-443}"
  local sni="${2:-www.microsoft.com}"
  local dest="${3:-${sni}:443}"
  local tag archive url tmp_dir xray_asset_arch
  local uuid key_output private_key public_key short_id server_ip link

  case "${ARCH}" in
    amd64) xray_asset_arch="64" ;;
    arm64) xray_asset_arch="arm64-v8a" ;;
    armv7) xray_asset_arch="arm32-v7a" ;;
    *) die "Unsupported Xray architecture: ${ARCH}" ;;
  esac

  tag="$(latest_github_release_tag "XTLS/Xray-core")"
  [[ -n "${tag}" ]] || die "Unable to resolve latest Xray-core release."

  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/xray.zip"
  url="https://github.com/XTLS/Xray-core/releases/download/$(github_release_tag_path "${tag}")/Xray-linux-${xray_asset_arch}.zip"

  download_file "${url}" "${archive}"
  unzip -q -o "${archive}" -d "${tmp_dir}/xray"
  install -m 0755 "${tmp_dir}/xray/xray" "${BIN_ROOT}/xray"
  rm -rf "${tmp_dir}"

  uuid="$(random_uuid)"
  key_output="$("${BIN_ROOT}/xray" x25519)"
  private_key="$(parse_xray_key "${key_output}" "private")"
  public_key="$(parse_xray_key "${key_output}" "public")"
  [[ -n "${private_key}" ]] || die "Failed to parse Xray REALITY private key from: xray x25519"
  [[ -n "${public_key}" ]] || die "Failed to parse Xray REALITY public key from: xray x25519"
  short_id="$(random_hex 8)"

  cat >"${CONFIG_ROOT}/xray.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-vision",
      "listen": "0.0.0.0",
      "port": ${port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${dest}",
          "xver": 0,
          "serverNames": [
            "${sni}"
          ],
          "privateKey": "${private_key}",
          "shortIds": [
            "${short_id}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF

  write_systemd_service "theladder-xray" "${BIN_ROOT}/xray run -config ${CONFIG_ROOT}/xray.json" "theLadder Xray VLESS REALITY Vision"
  open_firewall_port "${port}" "tcp"
  restart_service "theladder-xray"

  server_ip="$(public_ip)"
  [[ -n "${server_ip}" ]] || server_ip="<server-ip>"
  link="vless://${uuid}@${server_ip}:${port}?encryption=none&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&flow=xtls-rprx-vision#theLadder-Xray"

  cat >"${CONFIG_ROOT}/xray-client.txt" <<EOF
Xray VLESS REALITY Vision
server: ${server_ip}
port: ${port}
uuid: ${uuid}
flow: xtls-rprx-vision
security: reality
sni: ${sni}
fingerprint: chrome
public_key: ${public_key}
short_id: ${short_id}
link: ${link}
EOF

  log_info "Xray installed: ${tag}"
  echo
  cat "${CONFIG_ROOT}/xray-client.txt"
}

parse_xray_key() {
  local output="$1"
  local kind="$2"

  printf '%s\n' "${output}" | awk -v kind="${kind}" '
    {
      line = $0
      lower = tolower(line)
      compact = lower
      gsub(/[ _-]/, "", compact)
      target = kind "key"
      if (compact ~ target) {
        sub(/^[^:]*:[[:space:]]*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
        exit
      }
    }
  '
}

uninstall_xray() {
  require_root
  stop_disable_service "theladder-xray"
  rm -f "${CONFIG_ROOT}/xray.json" "${CONFIG_ROOT}/xray-client.txt"
  log_info "Xray removed."
}

status_xray() {
  systemctl --no-pager --full status theladder-xray
}

show_xray() {
  show_xray_client_info
  echo
  echo "Mihomo proxies:"
  echo "proxies:"
  print_xray_mihomo_proxy
}

show_xray_client_info() {
  if [[ -f "${CONFIG_ROOT}/xray-client.txt" ]]; then
    cat "${CONFIG_ROOT}/xray-client.txt"
  else
    die "Xray client info not found. Run: $0 install xray"
  fi
}

print_xray_mihomo_proxy() {
  local file="${CONFIG_ROOT}/xray-client.txt"
  local server port uuid flow sni fingerprint public_key short_id

  server="$(config_value "${file}" "server")"
  port="$(config_value "${file}" "port")"
  uuid="$(config_value "${file}" "uuid")"
  flow="$(config_value "${file}" "flow")"
  sni="$(config_value "${file}" "sni")"
  fingerprint="$(config_value "${file}" "fingerprint")"
  public_key="$(config_value "${file}" "public_key")"
  short_id="$(config_value "${file}" "short_id")"

  [[ -n "${fingerprint}" ]] || fingerprint="chrome"

  cat <<EOF
  - name: $(quote_yaml_string "theLadder-Xray")
    type: vless
    server: $(quote_yaml_string "${server}")
    port: ${port}
    uuid: $(quote_yaml_string "${uuid}")
    network: tcp
    tls: true
    udp: true
    flow: ${flow}
    servername: $(quote_yaml_string "${sni}")
    client-fingerprint: ${fingerprint}
    reality-opts:
      public-key: $(quote_yaml_string "${public_key}")
      short-id: $(quote_yaml_string "${short_id}")
    packet-encoding: xudp
    smux:
      enabled: false
EOF
}
