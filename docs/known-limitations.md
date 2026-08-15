# Known limitations

This document tracks limitations discovered during the DSM LXC lab work. A
limitation listed here may still be acceptable for the current phase if it is
isolated and reproducible.

## `lxc-attach` fails in the Phase 2 build

Status: open, non-blocking for Phase 3.

Observed in Virtual DSM:

```text
Unsupported config key "lxc.seccomp"
drop_capabilities: Function not implemented
Failed to attach to container
```

Current interpretation:

- LXC was intentionally built with seccomp integration disabled during Phase 2.
- DSM/Entware appears not to provide the capability operation behavior expected
  by LXC attach in this build profile.
- Foreground container start/stop still works and remains the trusted Phase 3
  measurement path.

Current handling:

- `scripts/probe-lab-features.sh` records `lxc-attach` as a warning.
- The probe then collects runtime evidence through foreground start.
- This must be revisited before treating the project as suitable for real
  long-running workloads.

Potential future paths:

- Build a second LXC profile with seccomp support enabled if dependencies are
  feasible on DSM/Entware.
- Investigate whether DSM capability headers or runtime behavior need an LXC
  compatibility patch.
- Keep `lxc-attach` unsupported and design operational tooling around
  foreground/console workflows, if acceptable for the target workloads.

## Container-side network interface listing is incomplete

Status: open, non-blocking for the detached veth lifecycle gate.

Observed in Virtual DSM during the first successful veth probe:

```text
OK: host veth appeared while detached container was running
OK: host veth disappeared after detached stop
OK: host veth absent after foreground probe
net_devices=
routes=1
ipv6_if=2
```

Current interpretation:

- Host-side veth creation and cleanup works.
- Container-side network evidence via `/proc/net/dev` is incomplete or empty in
  this minimal foreground `/bin/sh` probe.
- The route and IPv6 procfs files are present, so the network namespace itself
  is not simply absent.

Current handling:

- Phase 4 treats host-side veth lifecycle as validated.
- Container-side interface introspection remains a follow-up item before bridge
  or macvlan experiments.
- Network probe scripts also attempt `ip -o link show` inside the container
  when available.
