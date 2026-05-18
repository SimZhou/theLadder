#!/usr/bin/env bash

parse_lan_proxy_scope_arg() {
  local scope="${1:-}"
  shift || true

  while (($# > 0)); do
    case "$1" in
      --user|--user-mode)
        scope="user"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  echo "${scope}"
}

lan_proxy_effective_scope() {
  local requested_scope="${1:-}"

  if [[ "${requested_scope}" == "user" ]]; then
    echo "user"
    return
  fi

  if [[ "${EUID}" -eq 0 ]]; then
    echo "system"
  else
    echo "user"
  fi
}

install_lan_proxy() {
  local port="7890"
  local listen="0.0.0.0"
  local username="theladder"
  local password=""
  local install_scope="system"
  local target_user=""

  parse_lan_proxy_install_args "$@"
  target_user="$(lan_proxy_install_target_user "${install_scope}")"

  if [[ "${install_scope}" == "user" ]]; then
    install_lan_proxy_user_impl "${target_user}" "${port}" "${listen}" "${username}" "${password}"
    return
  fi

  if [[ "${EUID}" -ne 0 ]]; then
    log_info "检测到当前不是 root，改为用户级安装。"
    install_lan_proxy_user_impl "${target_user}" "${port}" "${listen}" "${username}" "${password}"
    return
  fi

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
  local target_user

  target_user="$(lan_proxy_install_target_user "user")"
  install_lan_proxy_user_impl "${target_user}" "$@"
}

install_lan_proxy_user_impl() {
  local target_user="$1"
  shift
  local port="7890"
  local listen="0.0.0.0"
  local username="theladder"
  local password=""

  parse_lan_proxy_install_args "$@"
  validate_lan_proxy_user_target "${target_user}"
  validate_port "${port}"
  validate_lan_proxy_listen "${listen}"
  validate_lan_proxy_credential "${username}" "用户名"
  [[ -z "${password}" ]] || validate_lan_proxy_credential "${password}" "密码"
  warn_lan_proxy_user_privileged_port "${port}"
  require_lan_proxy_user_tools
  detect_arch

  local user_home
  local user_bin_root
  local user_config_root
  local user_state_root
  local user_log_root
  local config_file
  local client_file
  local binary

  user_home="$(lan_proxy_user_home "${target_user}")"
  user_bin_root="${user_home}/.local/bin"
  user_config_root="${user_home}/.config/theladder"
  user_state_root="${user_home}/.local/state/theladder"
  user_log_root="${user_state_root}/log"
  config_file="${user_config_root}/lan-proxy.json"
  client_file="${user_config_root}/lan-proxy-client.txt"
  binary="${user_bin_root}/sing-box"

  mkdir -p "${user_bin_root}" "${user_config_root}" "${user_state_root}" "${user_log_root}"

  if [[ -z "${password}" ]]; then
    password="$(random_hex 16)"
  fi

  install_sing_box_binary "${user_bin_root}"
  write_lan_proxy_config "${config_file}" "${port}" "${listen}" "${username}" "${password}"
  "${binary}" check -c "${config_file}"
  write_lan_proxy_client_info "${client_file}" "${port}" "${listen}" "${username}" "${password}"
  ensure_lan_proxy_user_ownership "${target_user}" "${user_bin_root}" "${user_config_root}" "${user_state_root}"
  start_lan_proxy_user_for_target "${target_user}"

  log_info "LAN proxy 用户级安装完成。目标用户：${target_user}"
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
      --username)
        [[ $# -ge 2 ]] || die "--username requires a value."
        username="$2"
        shift 2
        ;;
      --password)
        [[ $# -ge 2 ]] || die "--password requires a value."
        password="$2"
        shift 2
        ;;
      --user|--user-mode)
        install_scope="user"
        shift
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

lan_proxy_install_target_user() {
  local install_scope="${1:-system}"

  if [[ "${install_scope}" == "user" ]]; then
    if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      echo "${SUDO_USER}"
      return
    fi
  fi

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    echo "${SUDO_USER}"
  else
    id -un
  fi
}

validate_lan_proxy_user_target() {
  local target_user="$1"

  [[ -n "${target_user}" ]] || die "无法确定用户级安装目标用户。"
  lan_proxy_user_home "${target_user}" >/dev/null
}

lan_proxy_user_home() {
  local target_user="$1"
  local home_dir=""

  if command_exists getent; then
    home_dir="$(getent passwd "${target_user}" | awk -F: 'NR == 1 { print $6 }')"
  fi

  if [[ -z "${home_dir}" ]]; then
    home_dir="$(awk -F: -v user="${target_user}" '$1 == user { print $6; exit }' /etc/passwd)"
  fi

  [[ -n "${home_dir}" ]] || die "无法解析用户 ${target_user} 的 home 目录。"
  echo "${home_dir}"
}

ensure_lan_proxy_user_ownership() {
  local target_user="$1"
  shift

  if [[ "${EUID}" -eq 0 && "${target_user}" != "root" ]]; then
    chown -R "${target_user}" "$@"
  fi
}

lan_proxy_run_as_target_user() {
  local target_user="$1"
  local user_home="$2"
  local command="$3"

  if [[ "${EUID}" -eq 0 && "${target_user}" != "$(id -un)" ]]; then
    if command_exists runuser; then
      runuser -u "${target_user}" -- env HOME="${user_home}" bash -lc "${command}"
      return
    fi
    if command_exists sudo; then
      sudo -u "${target_user}" env HOME="${user_home}" bash -lc "${command}"
      return
    fi
    su -s /bin/bash - "${target_user}" -c "${command}"
    return
  fi

  env HOME="${user_home}" bash -lc "${command}"
}

install_sing_box_binary() {
  local install_bin_root="$1"
  local tag version archive url tmp_dir sing_box_asset_arch binary_path

  if [[ -x "${install_bin_root}/sing-box" ]]; then
    log_info "sing-box already exists: ${install_bin_root}/sing-box"
    return
  fi

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
  local requested_scope=""
  local effective_scope=""

  requested_scope="$(parse_lan_proxy_scope_arg "" "$@")"
  effective_scope="$(lan_proxy_effective_scope "${requested_scope}")"

  if [[ "${effective_scope}" == "user" ]]; then
    uninstall_lan_proxy_user "$@"
    return
  fi

  require_root
  stop_disable_service "theladder-lan-proxy"
  rm -f "${CONFIG_ROOT}/lan-proxy.json" "${CONFIG_ROOT}/lan-proxy-client.txt"
  log_info "LAN proxy removed."
}

uninstall_lan_proxy_user() {
  local target_user
  local user_home
  local user_config_root
  local user_state_root
  local user_log_root

  target_user="$(lan_proxy_install_target_user "user")"
  user_home="$(lan_proxy_user_home "${target_user}")"
  user_config_root="${user_home}/.config/theladder"
  user_state_root="${user_home}/.local/state/theladder"
  user_log_root="${user_state_root}/log"

  stop_lan_proxy_user_for_target "${target_user}" || true
  rm -f \
    "${user_config_root}/lan-proxy.json" \
    "${user_config_root}/lan-proxy-client.txt" \
    "${user_state_root}/lan-proxy.pid" \
    "${user_log_root}/lan-proxy.log"
  log_info "LAN proxy 用户级安装已移除。目标用户：${target_user}"
}

status_lan_proxy() {
  local requested_scope=""
  local effective_scope=""

  requested_scope="$(parse_lan_proxy_scope_arg "" "$@")"
  effective_scope="$(lan_proxy_effective_scope "${requested_scope}")"

  if [[ "${effective_scope}" == "user" ]]; then
    status_lan_proxy_user "$@"
    return
  fi

  systemctl --no-pager --full status theladder-lan-proxy
}

start_lan_proxy() {
  local requested_scope=""
  local effective_scope=""

  requested_scope="$(parse_lan_proxy_scope_arg "" "$@")"
  effective_scope="$(lan_proxy_effective_scope "${requested_scope}")"

  if [[ "${effective_scope}" == "user" ]]; then
    start_lan_proxy_user "$@"
    return
  fi

  require_root
  systemctl start theladder-lan-proxy
  systemctl --no-pager --full status theladder-lan-proxy || true
  systemctl is-active --quiet theladder-lan-proxy || die "Service theladder-lan-proxy is not active after start."
}

start_lan_proxy_user() {
  local target_user

  target_user="$(lan_proxy_install_target_user "user")"
  start_lan_proxy_user_for_target "${target_user}"
}

start_lan_proxy_user_for_target() {
  local target_user="$1"
  local user_home
  local user_bin_root
  local user_config_root
  local user_state_root
  local user_log_root
  local binary
  local config_file
  local pid_file
  local log_file
  local port

  user_home="$(lan_proxy_user_home "${target_user}")"
  user_bin_root="${user_home}/.local/bin"
  user_config_root="${user_home}/.config/theladder"
  user_state_root="${user_home}/.local/state/theladder"
  user_log_root="${user_state_root}/log"
  binary="${user_bin_root}/sing-box"
  config_file="${user_config_root}/lan-proxy.json"
  pid_file="${user_state_root}/lan-proxy.pid"
  log_file="${user_log_root}/lan-proxy.log"

  [[ -x "${binary}" ]] || die "sing-box not found. Run: $0 install lan-proxy --user"
  [[ -f "${config_file}" ]] || die "lan-proxy config not found. Run: $0 install lan-proxy --user"
  mkdir -p "${user_state_root}" "${user_log_root}"

  if lan_proxy_user_is_running_for_target "${target_user}"; then
    log_info "LAN proxy user-mode is already running. pid=$(cat "${pid_file}")"
    return
  fi

  port="$(lan_proxy_config_listen_port "${config_file}")"
  [[ -n "${port}" ]] || die "Unable to read lan-proxy listen port from ${config_file}"
  assert_lan_proxy_port_available "${port}"

  local binary_q
  local config_q
  local log_q
  local pid_q
  local start_command

  printf -v binary_q '%q' "${binary}"
  printf -v config_q '%q' "${config_file}"
  printf -v log_q '%q' "${log_file}"
  printf -v pid_q '%q' "${pid_file}"
  start_command="nohup ${binary_q} run -c ${config_q} >>${log_q} 2>&1 & echo \$! > ${pid_q}"

  lan_proxy_run_as_target_user "${target_user}" "${user_home}" "${start_command}"
  sleep 1

  lan_proxy_user_is_running_for_target "${target_user}" || {
    rm -f "${pid_file}"
    die "LAN proxy user-mode failed to start. Check log: ${log_file}"
  }

  log_info "LAN proxy user-mode started. pid=$(cat "${pid_file}")"
}

lan_proxy_config_listen_port() {
  local config_file="$1"

  awk '
    /"listen_port"[[:space:]]*:/ {
      gsub(/[^0-9]/, "")
      print
      exit
    }
  ' "${config_file}"
}

assert_lan_proxy_port_available() {
  local port="$1"
  local owner=""

  owner="$(lan_proxy_port_owner "${port}")"
  if [[ -n "${owner}" ]]; then
    die "TCP port ${port} is already in use: ${owner}. Use another port, for example: $0 install lan-proxy --user --port 18080"
  fi
}

lan_proxy_port_owner() {
  local port="$1"

  if command_exists ss; then
    ss -ltnp 2>/dev/null | awk -v suffix=":${port}" '
      NR > 1 && $4 ~ suffix "$" {
        print $0
        exit
      }
    '
    return
  fi

  if command_exists lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR == 2 { print; exit }'
    return
  fi

  if command_exists netstat; then
    netstat -ltnp 2>/dev/null | awk -v suffix=":${port}" '
      NR > 2 && $4 ~ suffix "$" {
        print $0
        exit
      }
    '
  fi
}

stop_lan_proxy() {
  local requested_scope=""
  local effective_scope=""

  requested_scope="$(parse_lan_proxy_scope_arg "" "$@")"
  effective_scope="$(lan_proxy_effective_scope "${requested_scope}")"

  if [[ "${effective_scope}" == "user" ]]; then
    stop_lan_proxy_user "$@"
    return
  fi

  require_root
  systemctl stop theladder-lan-proxy
}

stop_lan_proxy_user() {
  local target_user

  target_user="$(lan_proxy_install_target_user "user")"
  stop_lan_proxy_user_for_target "${target_user}"
}

stop_lan_proxy_user_for_target() {
  local target_user="$1"
  local user_home
  local user_state_root
  local pid_file
  local pid

  user_home="$(lan_proxy_user_home "${target_user}")"
  user_state_root="${user_home}/.local/state/theladder"
  pid_file="${user_state_root}/lan-proxy.pid"

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

restart_lan_proxy() {
  local requested_scope=""
  local effective_scope=""

  requested_scope="$(parse_lan_proxy_scope_arg "" "$@")"
  effective_scope="$(lan_proxy_effective_scope "${requested_scope}")"

  if [[ "${effective_scope}" == "user" ]]; then
    restart_lan_proxy_user "$@"
    return
  fi

  require_root
  restart_service "theladder-lan-proxy"
}

restart_lan_proxy_user() {
  stop_lan_proxy_user "$@"
  start_lan_proxy_user "$@"
}

status_lan_proxy_user() {
  local target_user
  local user_home
  local user_config_root
  local user_state_root
  local user_log_root
  local pid_file
  local log_file

  target_user="$(lan_proxy_install_target_user "user")"
  user_home="$(lan_proxy_user_home "${target_user}")"
  user_config_root="${user_home}/.config/theladder"
  user_state_root="${user_home}/.local/state/theladder"
  user_log_root="${user_state_root}/log"
  pid_file="${user_state_root}/lan-proxy.pid"
  log_file="${user_log_root}/lan-proxy.log"

  if lan_proxy_user_is_running_for_target "${target_user}"; then
    echo "LAN proxy user-mode is running. pid=$(cat "${pid_file}")"
    echo "config: ${user_config_root}/lan-proxy.json"
    echo "log: ${log_file}"
  else
    echo "LAN proxy user-mode is not running."
    [[ -f "${log_file}" ]] && echo "log: ${log_file}"
    return 1
  fi
}

lan_proxy_user_is_running() {
  local target_user

  target_user="$(lan_proxy_install_target_user "user")"
  lan_proxy_user_is_running_for_target "${target_user}"
}

lan_proxy_user_is_running_for_target() {
  local target_user="$1"
  local user_home
  local user_state_root
  local pid_file
  local pid

  user_home="$(lan_proxy_user_home "${target_user}")"
  user_state_root="${user_home}/.local/state/theladder"
  pid_file="${user_state_root}/lan-proxy.pid"

  [[ -f "${pid_file}" ]] || return 1
  pid="$(cat "${pid_file}")"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

show_lan_proxy() {
  local requested_scope=""
  local effective_scope=""

  requested_scope="$(parse_lan_proxy_scope_arg "" "$@")"
  effective_scope="$(lan_proxy_effective_scope "${requested_scope}")"

  if [[ "${effective_scope}" == "user" ]]; then
    show_lan_proxy_user "$@"
    return
  fi

  print_section "LAN Proxy 客户端信息"
  show_lan_proxy_client_info
  print_section "Linux 临时代理环境变量"
  print_lan_proxy_env
  print_section "常用客户端地址"
  print_lan_proxy_endpoints
}

show_lan_proxy_user() {
  local target_user
  local user_home
  local user_config_root
  local client_file

  target_user="$(lan_proxy_install_target_user "user")"
  user_home="$(lan_proxy_user_home "${target_user}")"
  user_config_root="${user_home}/.config/theladder"
  client_file="${user_config_root}/lan-proxy-client.txt"

  print_section "LAN Proxy User-Mode 客户端信息"
  show_lan_proxy_client_info_file "${client_file}" "install lan-proxy --user"
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
