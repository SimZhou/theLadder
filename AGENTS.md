# Repository Instructions

This repository maintains Linux proxy deployment scripts. Keep the design simple, explicit, and operationally predictable.

## Design Principles

- Prefer one clear entrypoint over many loosely related scripts. New user-facing commands should live behind a single CLI surface.
- Keep install, uninstall, status, restart, and link/config display behavior consistent across protocols.
- Use `systemd` units for managed services on supported Linux distributions. Keep legacy `init.d` support only as a compatibility path when needed.
- Do not depend on Python 2. Shadowsocks/SSR support is legacy maintenance only; avoid new Python-based server dependencies.
- Prefer maintained upstream binaries for modern protocols:
  - Xray-core for `VLESS + REALITY + XTLS Vision`.
  - Hysteria2 for QUIC/UDP high-throughput fallback.
- Avoid opaque one-click third-party scripts for core installs. Download from official release sources when possible, verify architecture/OS, and keep generated configs local and readable.
- Keep defaults conservative: TCP 443 for Xray VLESS REALITY Vision, UDP 443 or configurable UDP port for Hysteria2, no unnecessary multiplexing by default.
- Treat firewall changes as scoped port openings, not broad firewall disablement.
- Separate reusable helpers from protocol installers: OS detection, dependency installation, download/extract, config rendering, service management, firewall, and output formatting.
- Make commands idempotent where practical. Re-running an install should update or repair the target service without duplicating files or units.

## Compatibility Direction

- SS/SSR remain available only for compatibility and migration. They should not block modern installs if Python 2 or old package names are unavailable.
- New development should prioritize Xray-core first, then Hysteria2.
- The CLI should make the recommended path obvious while still exposing legacy commands for users who need them.

## Code Style

- Bash is acceptable for this repository, but keep functions small and avoid hidden global state where practical.
- Quote variables, use `set -euo pipefail` in new scripts, and return clear error messages.
- Prefer readable generated JSON/config files over compact inline strings.
- Keep prompts minimal. Non-interactive flags should be supported for automation.
