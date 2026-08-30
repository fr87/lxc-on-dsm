# Phase 3 results: first DSM LXC runtime

Phase 3 has been validated in Virtual DSM with a deliberately minimal Alpine
container and no container networking.

Validated results:

- LXC userspace `6.0.6` starts a classic Linux container under DSM.
- Alpine minirootfs `3.24.1` boots to `/bin/sh`.
- The container can be started in foreground mode and stopped cleanly.
- A reproducible smoke test passes.
- The feature probe confirms hostname, kernel, PID namespace, cgroup, `/proc`,
  `/sys`, `/dev/pts` and disabled-network evidence.

Current expected feature-probe summary:

```text
WARN: lxc-attach failed; inspect log for DSM/Entware attach limitations
OK: container hostname is isolated
OK: container kernel evidence present
OK: PID namespace evidence present
OK: cgroup mount evidence present
OK: devpts evidence present
OK: network device evidence present while networking remained disabled

Result: FEATURE PROBE COMPLETE. Container was stopped and networking remained disabled.
```

The `lxc-attach` warning is not treated as a Phase 3 blocker because the
container runtime path itself is already proven via foreground start/stop.

Do not enable networking on the baseline `alpine-lab` container. Keep it as the
known-good recovery point while Phase 4 experiments are developed separately.
