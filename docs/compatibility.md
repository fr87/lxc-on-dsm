# Compatibility gate

Phase 1 produces evidence; a compilable LXC binary alone does not prove safe operation.

Hard Phase 1 requirements are mount, PID, UTS, IPC and network namespaces, plus usable base cgroups. `devpts`/PTY, capabilities, a usable root filesystem, container networking, pids cgroup and seccomp remain required before trusting real workloads, but missing proof for those does not by itself block userspace build experiments in Virtual DSM.

User namespaces are required for the preferred unprivileged design. If disabled, a privileged PoC is not an automatic fallback; it requires a separate security decision.

## Decision sequence

1. Run the collector in Virtual DSM.
2. Review `kernel-config.txt`, `summary.env`, and raw evidence.
3. Run the collector read-only on the physical DS224+.
4. Compare unpacked reports with `scripts/compare-reports.sh`.
5. Evaluate both reports with `scripts/evaluate-report.sh`.
6. Only then select LXC version, build method, storage and networking.

Seccomp, AppArmor, overlayfs, resource controllers and UID/GID mapping are separately assessed. Missing isolation controls can reduce acceptable scope even where LXC starts. A shell showing `Seccomp: 0` only proves that the shell is not confined; it does not prove that kernel seccomp support is absent.

## Current DS224+ and Virtual DSM observation

The first hardware and Virtual DSM reports from 2026-08-13 only differed by `generated_utc`. The kernel version, architecture and extracted kernel feature list matched. That makes Virtual DSM a useful development target for early userspace work, while networking and storage still need confirmation on the physical DS224+ before any real container workload is trusted.

## Preflight result classes

- `BLOCKED`: at least one hard requirement is missing or disabled. Do not attempt container startup.
- `INCONCLUSIVE`: no hard blocker was detected, but at least one hard requirement is still unproven. Gather more evidence before LXC startup.
- `PASS WITH CAUTION`: no hard blocker was detected, but warnings remain. Continue in Virtual DSM only.
- `WARN`: the report could not prove a feature or found a missing recommended feature. Treat unknown as work still to do, not as support.
