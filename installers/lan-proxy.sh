#!/usr/bin/env bash

LAN_PROXY_SERVICE_NAME="theladder-lan-proxy"

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
  local upstream=""
  local install_scope="system"
  local target_user=""

  parse_lan_proxy_install_args "$@"
  target_user="$(lan_proxy_install_target_user "${install_scope}")"

  if [[ "${install_scope}" == "user" ]]; then
    install_lan_proxy_user_parsed_impl "${target_user}" "${port}" "${listen}" "${username}" "${password}" "${upstream}"
    return
  fi

  if [[ "${EUID}" -ne 0 ]]; then
    log_info "检测到当前不是 root，改为用户级安装。"
    install_lan_proxy_user_parsed_impl "${target_user}" "${port}" "${listen}" "${username}" "${password}" "${upstream}"
    return
  fi

  install_lan_proxy_system_impl "${port}" "${listen}" "${username}" "${password}" "${upstream}"
}

install_lan_proxy_user() {
  local target_user
  local port="7890"
  local listen="0.0.0.0"
  local username="theladder"
  local password=""
  local upstream=""
  local install_scope="user"

  parse_lan_proxy_install_args "$@"
  target_user="$(lan_proxy_install_target_user "user")"
  install_lan_proxy_user_parsed_impl "${target_user}" "${port}" "${listen}" "${username}" "${password}" "${upstream}"
}

install_lan_proxy_system_impl() {
  local port="$1"
  local listen="$2"
  local username="$3"
  local password="$4"
  local upstream="$5"
  local client_file

  validate_port "${port}"
  validate_lan_proxy_listen "${listen}"
  warn_lan_proxy_upstream_credentials "${username}" "${password}" "${upstream}"
  require_root
  ensure_layout
  ensure_base_tools
  detect_arch

  lan_proxy_apply_upstream_defaults "${upstream}" "${username}" "${password}"
  username="${LAN_PROXY_USERNAME_RESULT}"
  password="${LAN_PROXY_PASSWORD_RESULT}"

  validate_lan_proxy_credential "${username}" "用户名"
  validate_lan_proxy_credential "${password}" "密码"
  validate_lan_proxy_upstream "${upstream}"

  install_sing_box_binary "${BIN_ROOT}"
  write_lan_proxy_config "${CONFIG_ROOT}/lan-proxy.json" "${port}" "${listen}" "${username}" "${password}" "${upstream}"
  "${BIN_ROOT}/sing-box" check -c "${CONFIG_ROOT}/lan-proxy.json"

  write_systemd_service "${LAN_PROXY_SERVICE_NAME}" "${BIN_ROOT}/sing-box run -c ${CONFIG_ROOT}/lan-proxy.json" "$(lan_proxy_service_description "${upstream}")"
  open_firewall_port "${port}" "tcp"
  restart_service "${LAN_PROXY_SERVICE_NAME}"

  client_file="${CONFIG_ROOT}/lan-proxy-client.txt"
  write_lan_proxy_client_info "${client_file}" "${port}" "${listen}" "${username}" "${password}" "${upstream}"

  log_info "LAN proxy 安装完成。"
  echo
  cat "${client_file}"
}

install_lan_proxy_user_parsed_impl() {
  local target_user="$1"
  local port="$2"
  local listen="$3"
  local username="$4"
  local password="$5"
  local upstream="$6"
  local user_home
  local user_bin_root
  local user_config_root
  local user_state_root
  local user_systemd_root
  local config_file
  local client_file
  local binary

  validate_lan_proxy_user_target "${target_user}"
  validate_port "${port}"
  validate_lan_proxy_listen "${listen}"
  warn_lan_proxy_upstream_credentials "${username}" "${password}" "${upstream}"
  warn_lan_proxy_user_privileged_port "${port}"
  require_lan_proxy_user_tools
  detect_arch

  lan_proxy_apply_upstream_defaults "${upstream}" "${username}" "${password}"
  username="${LAN_PROXY_USERNAME_RESULT}"
  password="${LAN_PROXY_PASSWORD_RESULT}"

  validate_lan_proxy_credential "${username}" "用户名"
  validate_lan_proxy_credential "${password}" "密码"
  validate_lan_proxy_upstream "${upstream}"

  user_home="$(lan_proxy_user_home "${target_user}")"
  user_bin_root="${user_home}/.local/bin"
  user_config_root="${user_home}/.config/theladder"
  user_state_root="${user_home}/.local/state/theladder"
  user_systemd_root="${user_home}/.config/systemd/user"
  config_file="${user_config_root}/lan-proxy.json"
  client_file="${user_config_root}/lan-proxy-client.txt"
  binary="${user_bin_root}/sing-box"

  mkdir -p "${user_bin_root}" "${user_config_root}" "${user_state_root}" "${user_systemd_root}"

  install_sing_box_binary "${user_bin_root}"
  write_lan_proxy_config "${config_file}" "${port}" "${listen}" "${username}" "${password}" "${upstream}"
  "${binary}" check -c "${config_file}"
  write_lan_proxy_client_info "${client_file}" "${port}" "${listen}" "${username}" "${password}" "${upstream}"
  write_lan_proxy_user_service "${target_user}" "${binary}" "${config_file}" "${upstream}"
  ensure_lan_proxy_user_ownership "${target_user}" "${user_bin_root}" "${user_config_root}" "${user_state_root}" "${user_systemd_root}"
  restart_lan_proxy_user_for_target "${target_user}"

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
      --upstream)
        [[ $# -ge 2 ]] || die "--upstream requires a value."
        upstream="$2"
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
        elif [[ -z "${upstream}" ]]; then
          upstream="$1"
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

warn_lan_proxy_upstream_credentials() {
  local username="$1"
  local password="$2"
  local upstream="$3"

  if [[ -n "${upstream}" && ("${username}" != "theladder" || -n "${password}") ]]; then
    log_info "检测到同时指定了 --upstream 和本地认证参数，将优先使用本地 --username/--password 作为 B 机器对外认证。"
  fi
}

require_lan_proxy_user_tools() {
  local missing=()

  for tool in curl tar openssl find awk sed head mktemp install systemctl; do
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

lan_proxy_user_uid() {
  local target_user="$1"

  id -u "${target_user}"
}

lan_proxy_user_runtime_dir() {
  local target_user="$1"

  echo "/run/user/$(lan_proxy_user_uid "${target_user}")"
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

lan_proxy_user_systemctl() {
  local target_user="$1"
  shift
  local user_home
  local runtime_dir
  local bus_path
  local home_q
  local runtime_q
  local bus_q
  local args=()
  local arg
  local arg_q
  local command

  user_home="$(lan_proxy_user_home "${target_user}")"
  runtime_dir="$(lan_proxy_user_runtime_dir "${target_user}")"
  bus_path="${runtime_dir}/bus"

  printf -v home_q '%q' "${user_home}"
  printf -v runtime_q '%q' "${runtime_dir}"

  for arg in "$@"; do
    printf -v arg_q '%q' "${arg}"
    args+=("${arg_q}")
  done

  command="export HOME=${home_q} XDG_RUNTIME_DIR=${runtime_q};"
  if [[ -S "${bus_path}" ]]; then
    printf -v bus_q '%q' "unix:path=${bus_path}"
    command="${command} export DBUS_SESSION_BUS_ADDRESS=${bus_q};"
  fi
  command="${command} systemctl --user ${args[*]}"

  lan_proxy_run_as_target_user "${target_user}" "${user_home}" "${command}"
}

lan_proxy_require_user_systemd() {
  local target_user="$1"

  lan_proxy_user_systemctl "${target_user}" --version >/dev/null 2>&1 || die "systemctl --user 不可用，请确认该机器启用了用户级 systemd。"
  lan_proxy_user_systemctl "${target_user}" daemon-reload >/dev/null 2>&1 || die "无法连接用户级 systemd。请先登录一次该用户，或由管理员执行 loginctl enable-linger ${target_user}。"
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

lan_proxy_apply_upstream_defaults() {
  local upstream="$1"
  local username="$2"
  local password="$3"
  local parsed_username=""
  local parsed_password=""
  local parsed_parts=()
  local line

  if [[ -n "${upstream}" ]]; then
    while IFS= read -r line; do
      parsed_parts+=("${line}")
    done < <(parse_lan_proxy_upstream_url "${upstream}")
    parsed_username="${parsed_parts[3]}"
    parsed_password="${parsed_parts[4]}"
  fi

  if [[ "${username}" == "theladder" && -z "${password}" && -n "${parsed_username}" && -n "${parsed_password}" ]]; then
    username="${parsed_username}"
    password="${parsed_password}"
  elif [[ -z "${password}" ]]; then
    password="$(random_hex 16)"
  fi

  LAN_PROXY_USERNAME_RESULT="${username}"
  LAN_PROXY_PASSWORD_RESULT="${password}"
}

validate_lan_proxy_upstream() {
  local upstream="$1"

  if [[ -n "${upstream}" ]]; then
    parse_lan_proxy_upstream_url "${upstream}" >/dev/null
  fi
}

parse_lan_proxy_upstream_url() {
  local upstream="$1"
  local scheme rest userinfo hostport username="" password="" host port

  [[ -n "${upstream}" ]] || die "上游代理地址不能为空。"
  [[ "${upstream}" == *"://"* ]] || die "上游代理地址必须包含协议头，例如 http:// 或 socks5://"

  scheme="${upstream%%://*}"
  rest="${upstream#*://}"

  case "${scheme}" in
    http|socks5|socks) ;;
    *) die "暂不支持的上游代理协议：${scheme}。当前仅支持 http:// 和 socks5://。" ;;
  esac

  [[ -n "${rest}" ]] || die "上游代理地址缺少主机和端口。"
  [[ "${rest}" != */* ]] || die "上游代理地址不能包含路径，仅支持 host:port。"

  if [[ "${rest}" == *"@"* ]]; then
    userinfo="${rest%%@*}"
    hostport="${rest#*@}"
    [[ "${userinfo}" == *:* ]] || die "上游代理认证必须是 username:password。"
    username="${userinfo%%:*}"
    password="${userinfo#*:}"
    validate_lan_proxy_credential "${username}" "上游代理用户名"
    validate_lan_proxy_credential "${password}" "上游代理密码"
  else
    hostport="${rest}"
  fi

  if [[ "${hostport}" == \[*\]:* ]]; then
    host="${hostport%\]:*}"
    host="${host#\[}"
    port="${hostport##*:}"
  else
    [[ "${hostport}" == *:* ]] || die "上游代理地址缺少端口。"
    host="${hostport%:*}"
    port="${hostport##*:}"
  fi

  [[ -n "${host}" ]] || die "上游代理地址缺少主机。"
  validate_port "${port}"

  printf '%s\n' "${scheme}" "${host}" "${port}" "${username}" "${password}"
}

lan_proxy_outbound_type() {
  local upstream_scheme="$1"

  case "${upstream_scheme}" in
    http) echo "http" ;;
    socks5|socks) echo "socks" ;;
    *) die "Unsupported upstream scheme: ${upstream_scheme}" ;;
  esac
}

lan_proxy_service_description() {
  local upstream="$1"

  if [[ -n "${upstream}" ]]; then
    echo "theLadder LAN HTTP/SOCKS relay proxy"
  else
    echo "theLadder LAN HTTP/SOCKS direct proxy"
  fi
}

write_lan_proxy_config() {
  local config_file="$1"
  local port="$2"
  local listen="$3"
  local username="$4"
  local password="$5"
  local upstream="$6"
  local upstream_parts=()
  local upstream_scheme=""
  local upstream_host=""
  local upstream_port=""
  local upstream_username=""
  local upstream_password=""
  local outbound_type="direct"
  local outbound_block='    {
      "type": "direct",
      "tag": "proxy-out"
    }'
  local line

  if [[ -n "${upstream}" ]]; then
    while IFS= read -r line; do
      upstream_parts+=("${line}")
    done < <(parse_lan_proxy_upstream_url "${upstream}")
    upstream_scheme="${upstream_parts[0]}"
    upstream_host="${upstream_parts[1]}"
    upstream_port="${upstream_parts[2]}"
    upstream_username="${upstream_parts[3]}"
    upstream_password="${upstream_parts[4]}"
    outbound_type="$(lan_proxy_outbound_type "${upstream_scheme}")"

    outbound_block='    {
      "type": "'"${outbound_type}"'",
      "tag": "proxy-out",
      "server": "'"${upstream_host}"'",
      "server_port": '"${upstream_port}"

    if [[ "${outbound_type}" == "socks" ]]; then
      outbound_block+='
      ,"version": "5"'
    fi

    if [[ -n "${upstream_username}" ]]; then
      outbound_block+='
      ,"username": "'"${upstream_username}"'",
      "password": "'"${upstream_password}"'"'
    fi

    outbound_block+='
    }'
  fi

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
${outbound_block}
  ],
  "route": {
    "final": "proxy-out"
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
  local upstream="$6"
  local server
  local url_host
  local mode_label="LAN Proxy HTTP/SOCKS Direct"

  server="$(lan_proxy_client_server "${listen}")"
  url_host="$(lan_proxy_url_host "${server}")"

  if [[ -n "${upstream}" ]]; then
    mode_label="LAN Proxy HTTP/SOCKS Relay"
  fi

  cat >"${client_file}" <<EOF
${mode_label}
server: ${server}
port: ${port}
listen: ${listen}
username: ${username}
password: ${password}
EOF

  if [[ -n "${upstream}" ]]; then
    cat >>"${client_file}" <<EOF
upstream: ${upstream}
EOF
  fi

  cat >>"${client_file}" <<EOF
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

write_lan_proxy_user_service() {
  local target_user="$1"
  local binary="$2"
  local config_file="$3"
  local upstream="$4"
  local user_home
  local user_systemd_root
  local unit_file

  user_home="$(lan_proxy_user_home "${target_user}")"
  user_systemd_root="${user_home}/.config/systemd/user"
  unit_file="${user_systemd_root}/${LAN_PROXY_SERVICE_NAME}.service"

  mkdir -p "${user_systemd_root}"

  cat >"${unit_file}" <<EOF
[Unit]
Description=$(lan_proxy_service_description "${upstream}")
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
ExecStart=${binary} run -c ${config_file}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=default.target
EOF
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
  stop_disable_service "${LAN_PROXY_SERVICE_NAME}"
  rm -f "${CONFIG_ROOT}/lan-proxy.json" "${CONFIG_ROOT}/lan-proxy-client.txt"
  log_info "LAN proxy 已移除。"
}

uninstall_lan_proxy_user() {
  local target_user
  local user_home
  local user_config_root
  local user_state_root
  local user_systemd_root

  target_user="$(lan_proxy_install_target_user "user")"
  user_home="$(lan_proxy_user_home "${target_user}")"
  user_config_root="${user_home}/.config/theladder"
  user_state_root="${user_home}/.local/state/theladder"
  user_systemd_root="${user_home}/.config/systemd/user"

  if [[ -f "${user_systemd_root}/${LAN_PROXY_SERVICE_NAME}.service" ]]; then
    lan_proxy_user_systemctl "${target_user}" disable --now "${LAN_PROXY_SERVICE_NAME}.service" >/dev/null 2>&1 || true
    lan_proxy_user_systemctl "${target_user}" daemon-reload >/dev/null 2>&1 || true
  fi

  rm -f \
    "${user_systemd_root}/${LAN_PROXY_SERVICE_NAME}.service" \
    "${user_config_root}/lan-proxy.json" \
    "${user_config_root}/lan-proxy-client.txt"
  rmdir "${user_state_root}" 2>/dev/null || true
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

  systemctl --no-pager --full status "${LAN_PROXY_SERVICE_NAME}"
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
  systemctl start "${LAN_PROXY_SERVICE_NAME}"
  systemctl --no-pager --full status "${LAN_PROXY_SERVICE_NAME}" || true
  systemctl is-active --quiet "${LAN_PROXY_SERVICE_NAME}" || die "Service ${LAN_PROXY_SERVICE_NAME} is not active after start."
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
  local binary
  local config_file

  user_home="$(lan_proxy_user_home "${target_user}")"
  user_bin_root="${user_home}/.local/bin"
  user_config_root="${user_home}/.config/theladder"
  binary="${user_bin_root}/sing-box"
  config_file="${user_config_root}/lan-proxy.json"

  [[ -x "${binary}" ]] || die "sing-box not found. Run: $0 install lan-proxy --user"
  [[ -f "${config_file}" ]] || die "lan-proxy config not found. Run: $0 install lan-proxy --user"

  lan_proxy_require_user_systemd "${target_user}"

  if lan_proxy_user_systemctl "${target_user}" is-active --quiet "${LAN_PROXY_SERVICE_NAME}.service"; then
    log_info "LAN proxy 用户级 systemd 服务已在运行。"
    return
  fi

  lan_proxy_user_systemctl "${target_user}" daemon-reload
  lan_proxy_user_systemctl "${target_user}" enable --now "${LAN_PROXY_SERVICE_NAME}.service"
  lan_proxy_user_systemctl "${target_user}" --no-pager --full status "${LAN_PROXY_SERVICE_NAME}.service" || true
  lan_proxy_user_systemctl "${target_user}" is-active --quiet "${LAN_PROXY_SERVICE_NAME}.service" || die "LAN proxy 用户级 systemd 服务启动失败。"
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
  systemctl stop "${LAN_PROXY_SERVICE_NAME}"
}

stop_lan_proxy_user() {
  local target_user

  target_user="$(lan_proxy_install_target_user "user")"
  stop_lan_proxy_user_for_target "${target_user}"
}

stop_lan_proxy_user_for_target() {
  local target_user="$1"
  local user_home
  local unit_file

  user_home="$(lan_proxy_user_home "${target_user}")"
  unit_file="${user_home}/.config/systemd/user/${LAN_PROXY_SERVICE_NAME}.service"

  [[ -f "${unit_file}" ]] || {
    log_info "LAN proxy user-mode 尚未安装。"
    return
  }

  lan_proxy_require_user_systemd "${target_user}"
  lan_proxy_user_systemctl "${target_user}" stop "${LAN_PROXY_SERVICE_NAME}.service"
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
  restart_service "${LAN_PROXY_SERVICE_NAME}"
}

restart_lan_proxy_user() {
  local target_user

  target_user="$(lan_proxy_install_target_user "user")"
  restart_lan_proxy_user_for_target "${target_user}"
}

restart_lan_proxy_user_for_target() {
  local target_user="$1"
  local user_home
  local user_config_root
  local config_file

  user_home="$(lan_proxy_user_home "${target_user}")"
  user_config_root="${user_home}/.config/theladder"
  config_file="${user_config_root}/lan-proxy.json"

  [[ -f "${config_file}" ]] || die "lan-proxy config not found. Run: $0 install lan-proxy --user"
  lan_proxy_require_user_systemd "${target_user}"

  lan_proxy_user_systemctl "${target_user}" daemon-reload
  lan_proxy_user_systemctl "${target_user}" restart "${LAN_PROXY_SERVICE_NAME}.service"
  lan_proxy_user_systemctl "${target_user}" --no-pager --full status "${LAN_PROXY_SERVICE_NAME}.service" || true
  lan_proxy_user_systemctl "${target_user}" is-active --quiet "${LAN_PROXY_SERVICE_NAME}.service" || die "LAN proxy 用户级 systemd 服务重启失败。"
}

status_lan_proxy_user() {
  local target_user
  local user_home
  local user_config_root

  target_user="$(lan_proxy_install_target_user "user")"
  user_home="$(lan_proxy_user_home "${target_user}")"
  user_config_root="${user_home}/.config/theladder"

  lan_proxy_require_user_systemd "${target_user}"
  echo "config: ${user_config_root}/lan-proxy.json"
  echo "journal: journalctl --user -u ${LAN_PROXY_SERVICE_NAME}.service -n 50 --no-pager"
  lan_proxy_user_systemctl "${target_user}" --no-pager --full status "${LAN_PROXY_SERVICE_NAME}.service"
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
