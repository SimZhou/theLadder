#!/usr/bin/env bash

# REALITY 伪装域名候选池：均需支持 TLS1.3 + HTTP/2，且不属于被教程用滥的目标。
# 刻意避开 www.microsoft.com 这类烂大街 SNI——它们最容易被 GFW 做定向 SNI 封锁，
# 一旦被封，同伪装域名的节点会成片失效（即使服务器、协议、密钥都完好）。
# 顺序即偏好：靠前的更稳。实测同一 dest 单次握手会抖动（Apple CDN 尤甚），
# 故 select 时用重试判定，不因偶发失败误杀一个本身可用的域名。
REALITY_SNI_CANDIDATES=(
  "cdn.jsdelivr.net"
  "www.apple.com"
  "www.icloud.com"
)

# 校验候选域名当前是否可作为 REALITY dest：必须协商出 TLS1.3 且 ALPN 支持 h2。
# 在服务器本机执行，顺带验证服务器到该 dest 的可达性（REALITY 回落要求）。
# 单次握手存在抖动，故重试数次，任意一次达标即视为可用。
reality_sni_is_valid() {
  local host="$1"
  local attempt out
  for attempt in 1 2 3; do
    out="$(echo | timeout 10 openssl s_client -connect "${host}:443" -servername "${host}" -alpn h2 2>/dev/null)" || continue
    if grep -q "Protocol  : TLSv1.3" <<<"${out}" && grep -q "ALPN protocol: h2" <<<"${out}"; then
      return 0
    fi
  done
  return 1
}

# 从候选池随机起点轮询，挑第一个实测可用的 SNI。
# 随机化让多台服务器倾向选用不同伪装域名，降低被批量识别、一锅端封锁的概率。
select_reality_sni() {
  local count="${#REALITY_SNI_CANDIDATES[@]}"
  local start=$((RANDOM % count))
  local i idx host
  for ((i = 0; i < count; i++)); do
    idx=$(((start + i) % count))
    host="${REALITY_SNI_CANDIDATES[idx]}"
    if reality_sni_is_valid "${host}"; then
      echo "${host}"
      return 0
    fi
  done
  # 全部探测失败（如服务器临时无法访问候选站点）时回退首项，不阻断安装。
  echo "${REALITY_SNI_CANDIDATES[0]}"
}

install_xray() {
  require_root
  ensure_layout
  ensure_base_tools
  ensure_bbr
  detect_arch

  local port="${1:-443}"
  local sni="${2:-}"
  local dest="${3:-}"
  local tag archive url tmp_dir xray_asset_arch
  local uuid key_output private_key public_key short_id server_ip link

  # 未显式指定 SNI 时自动优选；dest 默认跟随 SNI（同域名回落最自然）。
  if [[ -z "${sni}" ]]; then
    sni="$(select_reality_sni)"
    log_info "Auto-selected REALITY SNI: ${sni}"
  fi
  [[ -n "${dest}" ]] || dest="${sni}:443"

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
  print_section "Xray 原始客户端信息"
  show_xray_client_info
  print_section "Xray 的 mihomo 节点配置，复制到 proxies 下使用"
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
