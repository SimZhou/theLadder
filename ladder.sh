#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=installers/xray.sh
. "${SCRIPT_DIR}/installers/xray.sh"
# shellcheck source=installers/hysteria2.sh
. "${SCRIPT_DIR}/installers/hysteria2.sh"
# shellcheck source=installers/lan-proxy.sh
. "${SCRIPT_DIR}/installers/lan-proxy.sh"
# shellcheck source=installers/legacy.sh
. "${SCRIPT_DIR}/installers/legacy.sh"

usage() {
  cat <<'EOF'
theLadder - Linux 代理服务一键部署脚本

新手推荐：
  直接安装推荐组合。它会同时安装：
  1. Xray VLESS + REALITY + XTLS Vision：默认 TCP 443，兼容性好，建议作为主力节点。
  2. Hysteria2：默认 UDP 443，适合 UDP 可用、网络波动较大或需要高吞吐的场景。

  sudo ./ladder.sh install best

安装完成后查看客户端配置：
  sudo ./ladder.sh show best

  show 输出会包含两类内容：
  1. 原始客户端信息，适合手动填写客户端。
  2. mihomo 的 proxies 配置片段，适合复制到 Clash Verge Rev、FlClash 等 mihomo 客户端。

推荐安装：
  ./ladder.sh install best [xray_port] [hysteria2_port] [reality_sni]

单独安装现代协议：
  ./ladder.sh install xray [port] [reality_sni] [reality_dest]
  ./ladder.sh install hysteria2 [udp_port]

内网直通代理：
  sudo ./ladder.sh install lan-proxy [--port 7890] [--listen 0.0.0.0] [--username theladder] [--password password]
  ./ladder.sh install lan-proxy --user [--port 7890] [--listen 0.0.0.0] [--username theladder] [--password password]
  ./ladder.sh install lan-proxy --user --upstream http://user:pass@1.2.3.4:7890 --port 17890
  ./ladder.sh start|stop|restart|status|show|uninstall lan-proxy --user

  lan-proxy 默认会在一台能访问外网的机器上提供 HTTP/SOCKS5 混合代理。
  指定 `--upstream` 后，改为代理中转模式：B 机器开放 mixed 入口，再转发到上游 HTTP/SOCKS5 代理。
  `install lan-proxy` 默认做系统级安装；带 `--user` 或在非 root 下执行时，改为用户级安装。
  `--user` 模式使用用户级 systemd 管理服务。
  内网机器只需要能访问这台机器的监听地址和端口，就可以通过代理联网。

查看配置：
  ./ladder.sh show xray|hysteria2|lan-proxy|best

查看运行状态：
  ./ladder.sh status xray|hysteria2|lan-proxy|best

卸载：
  ./ladder.sh uninstall xray|hysteria2|lan-proxy|best

旧版 Shadowsocks/SSR 清理：
  ./ladder.sh legacy status
  ./ladder.sh legacy purge

默认值：
  Xray 端口：443/tcp
  Hysteria2 端口：443/udp
  LAN Proxy 端口：7890/tcp
  REALITY SNI：自动优选（不指定时从内置候选池实测挑选，多台服务器倾向不同域名以抗批量封锁）

协议选择建议：
  优先使用 Xray VLESS REALITY Vision，通常最稳。
  Hysteria2 作为备用或高吞吐节点，需要服务器和本地网络都放行 UDP 端口。
  不确定怎么选时，用 install best，并在客户端里同时保留两个节点。

客户端建议：
  iOS：优先 Stash 或 Shadowrocket；如果要免费手动填 VLESS/Hysteria2，可试 V2Box。
  macOS：推荐 Clash Verge Rev；也可以用 Clash Party/Mihomo Party。
  Android：推荐 FlClash 或 Clash Meta for Android；进阶用户可用 NekoBox。
  Linux 桌面：推荐 Clash Verge Rev；无桌面服务器可直接运行 mihomo core。
  Windows：推荐 Clash Verge Rev；也可以用 FlClash 或 Clash Party。
EOF
}

validate_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || die "端口不合法：${port}"
  ((port >= 1 && port <= 65535)) || die "端口不合法：${port}"
}

install_best() {
  local xray_port="${1:-443}"
  local hysteria_port="${2:-443}"
  local sni="${3:-}"

  validate_port "${xray_port}"
  validate_port "${hysteria_port}"

  # sni 留空时由 install_xray 自动优选；显式传入则透传并以同域名作为 dest。
  if [[ -n "${sni}" ]]; then
    install_xray "${xray_port}" "${sni}" "${sni}:443"
  else
    install_xray "${xray_port}"
  fi
  install_hysteria2 "${hysteria_port}"
}

uninstall_best() {
  uninstall_xray
  uninstall_hysteria2
}

status_best() {
  status_xray || true
  status_hysteria2 || true
}

show_best() {
  print_section "Xray 原始客户端信息"
  show_xray_client_info
  print_section "Hysteria2 原始客户端信息"
  show_hysteria2_client_info
  print_section "mihomo 节点配置，复制整个 proxies 片段使用"
  echo "proxies:"
  print_xray_mihomo_proxy
  print_hysteria2_mihomo_proxy
}

legacy_command() {
  local legacy_action="${1:-}"

  case "${legacy_action}" in
    status) status_legacy ;;
    purge) purge_legacy ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main() {
  local action="${1:-}"
  local target="${2:-}"

  case "${action}" in
    install)
      shift
      target="${1:-best}"
      shift || true
      case "${target}" in
        best) install_best "$@" ;;
        xray)
          validate_port "${1:-443}"
          install_xray "$@"
          ;;
        hysteria2)
          validate_port "${1:-443}"
          install_hysteria2 "$@"
          ;;
        lan-proxy) install_lan_proxy "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    uninstall)
      shift
      target="${1:-}"
      shift || true
      case "${target}" in
        best|"") uninstall_best ;;
        xray) uninstall_xray ;;
        hysteria2) uninstall_hysteria2 ;;
        lan-proxy) uninstall_lan_proxy "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    status)
      shift
      target="${1:-}"
      shift || true
      case "${target}" in
        best|"") status_best ;;
        xray) status_xray ;;
        hysteria2) status_hysteria2 ;;
        lan-proxy) status_lan_proxy "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    show)
      shift
      target="${1:-}"
      shift || true
      case "${target}" in
        best|"") show_best ;;
        xray) show_xray ;;
        hysteria2) show_hysteria2 ;;
        lan-proxy) show_lan_proxy "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    start)
      case "${target}" in
        lan-proxy)
          shift 2 || true
          start_lan_proxy "$@"
          ;;
        *) usage; exit 1 ;;
      esac
      ;;
    stop)
      case "${target}" in
        lan-proxy)
          shift 2 || true
          stop_lan_proxy "$@"
          ;;
        *) usage; exit 1 ;;
      esac
      ;;
    restart)
      case "${target}" in
        lan-proxy)
          shift 2 || true
          restart_lan_proxy "$@"
          ;;
        *) usage; exit 1 ;;
      esac
      ;;
    legacy)
      shift
      legacy_command "$@"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
