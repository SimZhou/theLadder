#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=installers/xray.sh
. "${SCRIPT_DIR}/installers/xray.sh"
# shellcheck source=installers/hysteria2.sh
. "${SCRIPT_DIR}/installers/hysteria2.sh"

usage() {
  cat <<'EOF'
theLadder - simple Linux proxy deployment

Recommended:
  ./ladder.sh install best [xray_port] [hysteria2_port] [reality_sni]

Modern protocols:
  ./ladder.sh install xray [port] [reality_sni] [reality_dest]
  ./ladder.sh install hysteria2 [udp_port]
  ./ladder.sh uninstall xray|hysteria2|best
  ./ladder.sh status xray|hysteria2|best
  ./ladder.sh show xray|hysteria2|best

Legacy compatibility:
  ./ladder.sh legacy ss <password> [port]
  ./ladder.sh legacy ssr
  ./ladder.sh legacy sslink
  ./ladder.sh legacy bbr

Defaults:
  xray_port: 443/tcp
  hysteria2_port: 443/udp
  reality_sni: www.microsoft.com
EOF
}

validate_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || die "Invalid port: ${port}"
  ((port >= 1 && port <= 65535)) || die "Invalid port: ${port}"
}

install_best() {
  local xray_port="${1:-443}"
  local hysteria_port="${2:-443}"
  local sni="${3:-www.microsoft.com}"

  validate_port "${xray_port}"
  validate_port "${hysteria_port}"

  install_xray "${xray_port}" "${sni}" "${sni}:443"
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
  show_xray
  echo
  show_hysteria2
}

legacy_command() {
  local legacy_action="${1:-}"
  shift || true

  case "${legacy_action}" in
    ss)
      log_warn "SS is legacy and may fail on modern systems without Python 2. Prefer: ./ladder.sh install xray"
      "${SCRIPT_DIR}/ss-fly.sh" -i "$@"
      ;;
    ssr)
      log_warn "SSR is legacy and depends on an external installer. Prefer: ./ladder.sh install xray"
      "${SCRIPT_DIR}/ss-fly.sh" -ssr
      ;;
    sslink)
      "${SCRIPT_DIR}/ss-fly.sh" -sslink
      ;;
    bbr)
      "${SCRIPT_DIR}/ss-fly.sh" -bbr
      ;;
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
        *) usage; exit 1 ;;
      esac
      ;;
    uninstall)
      case "${target}" in
        best|"") uninstall_best ;;
        xray) uninstall_xray ;;
        hysteria2) uninstall_hysteria2 ;;
        *) usage; exit 1 ;;
      esac
      ;;
    status)
      case "${target}" in
        best|"") status_best ;;
        xray) status_xray ;;
        hysteria2) status_hysteria2 ;;
        *) usage; exit 1 ;;
      esac
      ;;
    show)
      case "${target}" in
        best|"") show_best ;;
        xray) show_xray ;;
        hysteria2) show_hysteria2 ;;
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
