# Repository Instructions

This repository maintains Linux proxy deployment scripts. Keep the design simple, explicit, and operationally predictable.

## Design Principles

- Prefer one clear entrypoint over many loosely related scripts. New user-facing commands should live behind a single CLI surface.
- `lan-proxy` must remain a single target. User-mode behavior should be selected with `--user`, not by introducing a separate `lan-proxy-user` command again.
- `lan-proxy --user` should be managed by user-level `systemd` units. Do not reintroduce `nohup`, pid files, or ad-hoc background-process management for user mode.
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

- SS/SSR installers are no longer maintained in this repository. Keep only status and purge helpers for removing existing legacy deployments.
- Do not remove or stop existing SS/SSR services as part of a modern install unless the user explicitly asks. Modern services must be able to run in parallel on separate ports during migration.
- New development should prioritize Xray-core first, then Hysteria2.
- The CLI should make the recommended path obvious while exposing only necessary legacy cleanup commands.

## Verified Defaults

- Xray installs should generate `VLESS + REALITY + XTLS Vision` on TCP `443` by default, with `servername`/`dest` defaulting to `www.microsoft.com`.
- Hysteria2 installs should be treated as a high-throughput fallback and should support a configurable UDP port. Use UDP `8443` in examples when Xray already uses TCP `443`.
- Generated client output must include enough fields for mihomo clients: server, port, uuid/password, `flow`, `servername`/SNI, public key, short id, and obfs settings where applicable.
- Never write private server keys, generated passwords, or real node credentials into repository docs or examples. Use placeholders in committed documentation.

## Operational Checks

- After writing a systemd unit, verify the service is actually active after restart. A transient successful `systemctl restart` is not enough.
- Xray REALITY key parsing must tolerate upstream output formatting differences from `xray x25519`; fail fast if either private or public key is empty.
- Firewall helpers should warn when no local firewall manager is active, but cloud security groups still need to be opened manually.

## Code Style

- Bash is acceptable for this repository, but keep functions small and avoid hidden global state where practical.
- Quote variables, use `set -euo pipefail` in new scripts, and return clear error messages.
- Prefer readable generated JSON/config files over compact inline strings.
- Keep prompts minimal. Non-interactive flags should be supported for automation.
