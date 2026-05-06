#!/usr/bin/env bash

LAN_PROXY_USER_BIN_ROOT="${HOME}/.local/bin"
LAN_PROXY_USER_CONFIG_ROOT="${HOME}/.config/theladder"
LAN_PROXY_USER_STATE_ROOT="${HOME}/.local/state/theladder"
LAN_PROXY_USER_LOG_ROOT="${HOME}/.local/state/theladder/log"

install_lan_proxy() {
  local port="7890"
  local listen="0.0.0.0"
  local username="theladder"
  local password=""

  parse_lan_proxy_install_args "$@"
  validate_port "${port}"
  validate_lan_proxy_listen "${listen}"
  validate_lan_proxy_credential "${username}" "用户名"
  [[ -z "${password}" ]] || validate_lan_proxy_credential "${password}" "密码"

  require_root
  ensure_layout
  ensure_base_tools
  detect_arch

  if [[ -z "${password}" ]]; then
    password="$(random_hex 16)"
  fi

  install_sing_box_binary "${BIN_ROOT}"
  write_lan_proxy_config "${CONFIG_ROOT}/lan-proxy.json" "${port}" "${listen}" "${username}" "${password}"
  "${BIN_ROOT}/sing-box" check -c "${CONFIG_ROOT}/lan-proxy.json"

  write_systemd_service "theladder-lan-proxy" "${BIN_ROOT}/sing-box run -c ${CONFIG_ROOT}/lan-proxy.json" "theLadder LAN HTTP/SOCKS direct proxy"
  open_firewall_port "${port}" "tcp"
  restart_service "theladder-lan-proxy"
  write_lan_proxy_client_info "${CONFIG_ROOT}/lan-proxy-client.txt" "${port}" "${listen}" "${username}" "${password}"

  log_info "LAN proxy installed."
  echo
  cat "${CONFIG_ROOT}/lan-proxy-client.txt"
}

install_lan_proxy_user() {
  local port="7890"
  local listen="0.0.0.0"
  local username="theladder"
  local password=""
  local config_file="${LAN_PROXY_USER_CONFIG_ROOT}/lan-proxy.json"
  local client_file="${LAN_PROXY_USER_CONFIG_ROOT}/lan-proxy-client.txt"
  local binary="${LAN_PROXY_USER_BIN_ROOT}/sing-box"

  parse_lan_proxy_install_args "$@"
  validate_port "${port}"
  validate_lan_proxy_listen "${listen}"
  validate_lan_proxy_credential "${username}" "用户名"
  [[ -z "${password}" ]] || validate_lan_proxy_credential "${password}" "密码"
  warn_lan_proxy_user_privileged_port "${port}"
  require_lan_proxy_user_tools
  detect_arch

  mkdir -p "${LAN_PROXY_USER_BIN_ROOT}" "${LAN_PROXY_USER_CONFIG_ROOT}" "${LAN_PROXY_USER_STATE_ROOT}" "${LAN_PROXY_USER_LOG_ROOT}"

  if [[ -z "${password}" ]]; then
    password="$(random_hex 16)"
  fi

  install_sing_box_binary "${LAN_PROXY_USER_BIN_ROOT}"
  write_lan_proxy_config "${config_file}" "${port}" "${listen}" "${username}" "${password}"
  "${binary}" check -c "${config_file}"
  write_lan_proxy_client_info "${client_file}" "${port}" "${listen}" "${username}" "${password}"
  start_lan_proxy_user

  log_info "LAN proxy user-mode installed."
  echo
  cat "${client_file}"
}

parse_lan_proxy_install_args() {
  while (($# > 0)); do
    case "$1" in
      --port)
        [[ $# -ge 2 ]] || die "--port requires a value."
        port="$2"
        shift 2
        ;;
      --listen)
        [[ $# -ge 2 ]] || die "--listen requires a value."
        listen="$2"
        shift 2
        ;;
      --user|--username)
        [[ $# -ge 2 ]] || die "$1 requires a value."
        username="$2"
        shift 2
        ;;
      --password)
        [[ $# -ge 2 ]] || die "--password requires a value."
        password="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --*)
        die "Unknown lan-proxy option: $1"
        ;;
      *)
        if [[ "${port}" == "7890" ]]; then
          port="$1"
        elif [[ "${listen}" == "0.0.0.0" ]]; then
          listen="$1"
        elif [[ "${username}" == "theladder" ]]; then
          username="$1"
        elif [[ -z "${password}" ]]; then
          password="$1"
        else
          die "Too many lan-proxy arguments."
        fi
        shift
        ;;
    esac
  done
}

validate_lan_proxy_credential() {
  local value="$1"
  local label="$2"

  [[ -n "${value}" ]] || die "${label}不能为空。"
  [[ "${value}" =~ ^[A-Za-z0-9._~-]+$ ]] || die "${label}只能包含 ASCII 字母、数字和 ._~-，以便直接放入代理 URL。"
}

validate_lan_proxy_listen() {
  local value="$1"

  [[ -n "${value}" ]] || die "监听地址不能为空。"
  [[ "${value}" =~ ^[A-Za-z0-9:._-]+$ ]] || die "监听地址只能包含 ASCII 字母、数字和 :._-"
}

require_lan_proxy_user_tools() {
  local missing=()

  for tool in curl tar openssl find awk sed head mktemp install; do
    command_exists "${tool}" || missing+=("${tool}")
  done

  if ((${#missing[@]} > 0)); then
    die "缺少必要命令：${missing[*]}。无 root 模式不会自动安装系统依赖，请先让管理员安装或手动准备这些命令。"
  fi
}

warn_lan_proxy_user_privileged_port() {
  local port="$1"

  if ((port < 1024)); then
    log_warn "无 root 模式通常不能监听 1024 以下端口，建议使用 7890、8080 等高位端口。"
  fi
}

install_sing_box_binary() {
  local install_bin_root="$1"
  local tag version archive url tmp_dir sing_box_asset_arch binary_path

  case "${ARCH}" in
    amd64) sing_box_asset_arch="amd64" ;;
    arm64) sing_box_asset_arch="arm64" ;;
    armv7) sing_box_asset_arch="armv7" ;;
    *) die "Unsupported sing-box architecture: ${ARCH}" ;;
  esac

  tag="$(latest_github_release_tag "SagerNet/sing-box")"
  [[ -n "${tag}" ]] || die "Unable to resolve latest sing-box release."
  version="${tag#v}"

  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/sing-box.tar.gz"
  url="https://github.com/SagerNet/sing-box/releases/download/$(github_release_tag_path "${tag}")/sing-box-${version}-linux-${sing_box_asset_arch}.tar.gz"

  download_file "${url}" "${archive}"
  tar -xzf "${archive}" -C "${tmp_dir}"
  binary_path="$(find "${tmp_dir}" -type f -name sing-box -perm -111 | head -n 1)"
  [[ -n "${binary_path}" ]] || die "sing-box binary not found in release archive."
  install -m 0755 "${binary_path}" "${install_bin_root}/sing-box"
  rm -rf "${tmp_dir}"

  log_info "sing-box installed: ${tag}"
}

write_lan_proxy_config() {
  local config_file="$1"
  local port="$2"
  local listen="$3"
  local username="$4"
  local password="$5"

  cat >"${config_file}" <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "lan-proxy-in",
      "listen": "${listen}",
      "listen_port": ${port},
      "users": [
        {
          "username": "${username}",
          "password": "${password}"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
}

write_lan_proxy_client_info() {
  local client_file="$1"
  local port="$2"
  local listen="$3"
  local username="$4"
  local password="$5"
  local server url_host

  server="$(lan_proxy_client_server "${listen}")"
  url_host="$(lan_proxy_url_host "${server}")"

  cat >"${client_file}" <<EOF
LAN Proxy HTTP/SOCKS Direct
server: ${server}
port: ${port}
listen: ${listen}
username: ${username}
password: ${password}
http_proxy: http://${username}:${password}@${url_host}:${port}
https_proxy: http://${username}:${password}@${url_host}:${port}
all_proxy: socks5://${username}:${password}@${url_host}:${port}
EOF
}

lan_proxy_client_server() {
  local listen="$1"
  local lan_ip

  case "${listen}" in
    0.0.0.0|::)
      lan_ip="$(detect_lan_ip)"
      [[ -n "${lan_ip}" ]] || lan_ip="<lan-proxy-lan-ip>"
      echo "${lan_ip}"
      ;;
    *)
      echo "${listen}"
      ;;
  esac
}

lan_proxy_url_host() {
  local server="$1"

  if [[ "${server}" == *:* && "${server}" != \[* ]]; then
    echo "[${server}]"
  else
    echo "${server}"
  fi
}

detect_lan_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == "src") {
            print $(i + 1)
            exit
          }
        }
      }
    '
}

uninstall_lan_proxy() {
  require_root
  stop_disable_service "theladder-lan-proxy"
  rm -f "${CONFIG_ROOT}/lan-proxy.json" "${CONFIG_ROOT}/lan-proxy-client.txt"
  log_info "LAN proxy removed."
}

uninstall_lan_proxy_user() {
  stop_lan_proxy_user || true
  rm -f \
    "${LAN_PROXY_USER_CONFIG_ROOT}/lan-proxy.json" \
    "${LAN_PROXY_USER_CONFIG_ROOT}/lan-proxy-client.txt" \
    "${LAN_PROXY_USER_STATE_ROOT}/lan-proxy.pid" \
    "${LAN_PROXY_USER_LOG_ROOT}/lan-proxy.log"
  log_info "LAN proxy user-mode removed."
}

status_lan_proxy() {
  systemctl --no-pager --full status theladder-lan-proxy
}

start_lan_proxy_user() {
  local binary="${LAN_PROXY_USER_BIN_ROOT}/sing-box"
  local config_file="${LAN_PROXY_USER_CONFIG_ROOT}/lan-proxy.json"
  local pid_file="${LAN_PROXY_USER_STATE_ROOT}/lan-proxy.pid"
  local log_file="${LAN_PROXY_USER_LOG_ROOT}/lan-proxy.log"

  [[ -x "${binary}" ]] || die "sing-box not found. Run: $0 install lan-proxy-user"
  [[ -f "${config_file}" ]] || die "lan-proxy config not found. Run: $0 install lan-proxy-user"
  mkdir -p "${LAN_PROXY_USER_STATE_ROOT}" "${LAN_PROXY_USER_LOG_ROOT}"

  if lan_proxy_user_is_running; then
    log_info "LAN proxy user-mode is already running. pid=$(cat "${pid_file}")"
    return
  fi

  nohup "${binary}" run -c "${config_file}" >>"${log_file}" 2>&1 &
  echo "$!" >"${pid_file}"
  sleep 1

  lan_proxy_user_is_running || {
    rm -f "${pid_file}"
    die "LAN proxy user-mode failed to start. Check log: ${log_file}"
  }

  log_info "LAN proxy user-mode started. pid=$(cat "${pid_file}")"
}

stop_lan_proxy_user() {
  local pid_file="${LAN_PROXY_USER_STATE_ROOT}/lan-proxy.pid"
  local pid

  if [[ ! -f "${pid_file}" ]]; then
    log_info "LAN proxy user-mode is not running."
    return
  fi

  pid="$(cat "${pid_file}")"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    sleep 1
    if kill -0 "${pid}" 2>/dev/null; then
      kill -TERM "${pid}" 2>/dev/null || true
    fi
  fi

  rm -f "${pid_file}"
  log_info "LAN proxy user-mode stopped."
}

restart_lan_proxy_user() {
  stop_lan_proxy_user
  start_lan_proxy_user
}

status_lan_proxy_user() {
  local pid_file="${LAN_PROXY_USER_STATE_ROOT}/lan-proxy.pid"
  local log_file="${LAN_PROXY_USER_LOG_ROOT}/lan-proxy.log"

  if lan_proxy_user_is_running; then
    echo "LAN proxy user-mode is running. pid=$(cat "${pid_file}")"
    echo "config: ${LAN_PROXY_USER_CONFIG_ROOT}/lan-proxy.json"
    echo "log: ${log_file}"
  else
    echo "LAN proxy user-mode is not running."
    [[ -f "${log_file}" ]] && echo "log: ${log_file}"
    return 1
  fi
}

lan_proxy_user_is_running() {
  local pid_file="${LAN_PROXY_USER_STATE_ROOT}/lan-proxy.pid"
  local pid

  [[ -f "${pid_file}" ]] || return 1
  pid="$(cat "${pid_file}")"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

show_lan_proxy() {
  print_section "LAN Proxy 客户端信息"
  show_lan_proxy_client_info
  print_section "Linux 临时代理环境变量"
  print_lan_proxy_env
  print_section "常用客户端地址"
  print_lan_proxy_endpoints
}

show_lan_proxy_user() {
  local client_file="${LAN_PROXY_USER_CONFIG_ROOT}/lan-proxy-client.txt"

  print_section "LAN Proxy User-Mode 客户端信息"
  show_lan_proxy_client_info_file "${client_file}" "install lan-proxy-user"
  print_section "Linux 临时代理环境变量"
  print_lan_proxy_env_file "${client_file}"
  print_section "常用客户端地址"
  print_lan_proxy_endpoints_file "${client_file}"
}

show_lan_proxy_client_info() {
  show_lan_proxy_client_info_file "${CONFIG_ROOT}/lan-proxy-client.txt" "install lan-proxy"
}

show_lan_proxy_client_info_file() {
  local file="$1"
  local install_command="$2"

  if [[ -f "${file}" ]]; then
    cat "${file}"
  else
    die "LAN proxy client info not found. Run: $0 ${install_command}"
  fi
}

print_lan_proxy_env() {
  print_lan_proxy_env_file "${CONFIG_ROOT}/lan-proxy-client.txt"
}

print_lan_proxy_env_file() {
  local file="$1"
  local http_proxy https_proxy all_proxy

  http_proxy="$(config_value "${file}" "http_proxy")"
  https_proxy="$(config_value "${file}" "https_proxy")"
  all_proxy="$(config_value "${file}" "all_proxy")"

  cat <<EOF
export http_proxy="${http_proxy}"
export https_proxy="${https_proxy}"
export all_proxy="${all_proxy}"
EOF
}

print_lan_proxy_endpoints() {
  print_lan_proxy_endpoints_file "${CONFIG_ROOT}/lan-proxy-client.txt"
}

print_lan_proxy_endpoints_file() {
  local file="$1"
  local server port username password url_host

  server="$(config_value "${file}" "server")"
  port="$(config_value "${file}" "port")"
  username="$(config_value "${file}" "username")"
  password="$(config_value "${file}" "password")"
  url_host="$(lan_proxy_url_host "${server}")"

  cat <<EOF
HTTP: http://${username}:${password}@${url_host}:${port}
SOCKS5: socks5://${username}:${password}@${url_host}:${port}
EOF
}
