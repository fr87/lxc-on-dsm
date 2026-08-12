# Compatibility gate

Phase 1 produces evidence; a compilable LXC binary alone does not prove safe operation.

Hard requirements are mount, PID, UTS, IPC and network namespaces; usable cgroups; `devpts`/PTY and capabilities; a usable root filesystem; and container networking (preferably `veth` plus bridge).

User namespaces are required for the preferred unprivileged design. If disabled, a privileged PoC is not an automatic fallback; it requires a separate security decision.

## Decision sequence

1. Run the collector in Virtual DSM.
2. Review `kernel-config.txt`, `summary.env`, and raw evidence.
3. Run the collector read-only on the physical DS224+.
4. Compare unpacked reports with `scripts/compare-reports.sh`.
5. Mark every requirement confirmed, missing, or unknown. Unknown is not supported.
6. Only then select LXC version, build method, storage and networking.

Seccomp, AppArmor, overlayfs, resource controllers and UID/GID mapping are separately assessed. Missing isolation controls can reduce acceptable scope even where LXC starts.
