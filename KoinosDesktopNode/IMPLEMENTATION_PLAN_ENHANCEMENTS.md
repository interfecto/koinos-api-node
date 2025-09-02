# KoinosDesktopNode — Implementation Plan Enhancements

This document proposes concrete upgrades to the desktop app plan based on Koinos node operations: roles/profiles, microservices, configuration, security, management, and block production.

## Node Roles & Compose Profiles
- Add a first‑run “Node Mode” selector: Light/Full, API, Block Producer. Map to `COMPOSE_PROFILES` and show which services enable.
- Pin a specific Koinos release tag/branch and expose an "Update core images" action (`docker compose pull`).

## Microservices Readiness & Health
- Gate "Running" state on readiness: recent head info (`chain.get_head_info`), minimum peers, and RPC responsiveness.
- Display per‑service status (chain, JSON‑RPC/REST, P2P) with last check time and errors.

## Configuration UI (Safe Defaults)
- Bind all APIs to `127.0.0.1` by default. Add explicit toggle to expose ports with warning and doc link.
- Offer "pruned vs archival" if supported; show disk impact and enforce free‑space preflight (≥60GB) and RAM check (≥4GB).
- Add port reachability test (P2P inbound) and short NAT/firewall tips.

## Security Hardening
- Require non‑root Docker (user in `docker` group); fail fast otherwise.
- Never store secrets (producer keys) in plaintext; use OS keychain via Tauri and inject at runtime.
- If APIs are exposed without auth, require user acknowledgment and surface risks. Provide quick link to secure config.

## Block Production Wizard
- Separate guided flow: key generation/import, secure storage, profile/service enablement, and a dry‑run validator.
- One‑click "Disable producer" and clear visual state (producing vs non‑producing).

## Management & Monitoring
- Use Compose restart policies in configuration (avoid CLI `--restart`). Add toggles for "Autostart on login" using OS facilities.
- Add actions: Pull updates, prune old images, open logs, export diagnostics bundle, and run quick health probes.
- Show verbose Compose errors with a "Copy details" button.

## Snapshot & Recovery
- Let users choose snapshot vs. full sync. Validate checksum if available; show size/time estimate and progress.
- Add “Reset with snapshot” flow that safely stops, backs up, restores, and restarts services.

## Cross‑Platform Preflight
- Windows: check WSL2/Docker Desktop state and required features.
- macOS: verify Docker Desktop and guide virtualization settings.
- Linux: verify cgroups and network prerequisites; offer `sudo usermod -aG docker $USER` guidance.

## Implementation Notes (repo integration)
- `src-tauri/src/node_manager.rs`: profile selection, compose start using restart policy in Compose files, port exposure toggles, health probes, snapshot workflows.
- `src-tauri/src/lib.rs`: new commands for update/pull, diagnostics export, producer setup.
- React UI: add Node Mode selector, Producer Wizard, Health panel, and Settings for ports/pruning/autostart.

## Acceptance Criteria
- Selecting a mode applies correct profiles and shows enabled services.
- "Running" only after head height threshold and peers met; per‑service status visible.
- APIs bind to localhost by default; exposing ports requires explicit confirmation and updates config accordingly.
- Producer keys stored in OS keychain; enable/disable producer works without plaintext secrets.
- Update/pull/prune/logs/diagnostics actions function across platforms.
- Snapshot install and reset workflows complete with progress and error feedback.

## References
- Running a node: https://docs.koinos.io/validators/guides/running-a-node/
- Compose profiles: https://docs.koinos.io/validators/docker-compose-profiles/
- Microservices: https://docs.koinos.io/validators/microservices/
- Configuration: https://docs.koinos.io/validators/configuration/
- Node security: https://docs.koinos.io/validators/node-security/
- Node management: https://docs.koinos.io/validators/node-management/
- Block production: https://docs.koinos.io/validators/guides/block-production/
