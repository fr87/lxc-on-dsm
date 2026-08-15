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

## `/proc/net/dev` interface listing can be incomplete

Status: observed, non-blocking for the detached veth lifecycle gate.

Observed in Virtual DSM during the first successful veth probe:

```text
OK: host veth appeared while detached container was running
OK: host veth disappeared after detached stop
OK: host veth absent after foreground probe
net_devices=
ip_link_count=3
routes=1
ipv6_if=2
```

Current interpretation:

- Host-side veth creation and cleanup works.
- Container-side interfaces exist; `ip -o link show` reported three links in a
  follow-up run.
- Container-side network evidence via `/proc/net/dev` is incomplete or empty in
  this minimal foreground `/bin/sh` probe.
- The route and IPv6 procfs files are present, so the network namespace itself
  is not simply absent.

Current handling:

- Phase 4 treats host-side veth lifecycle as validated.
- Use `ip -o link show` as the preferred container-side interface signal when
  available.
- Do not treat empty `net_devices=` by itself as evidence that the network
  namespace lacks interfaces.

## Macvlan host-to-container communication fails without host shim

Status: observed, non-blocking for outbound LAN validation.

Observed in Virtual DSM:

```text
dhcp_status=OK
gateway_ping=OK
internet_ping=OK
ip_plain=10.26.88.237
host_ping=FAIL
```

Current interpretation:

- The container can reach the LAN and internet via macvlan on `eth0`.
- The DSM host does not directly reach the macvlan container IP through the
  parent interface in the current Virtual DSM test.
- This is expected Linux/macvlan behavior and is not evidence that container
  outbound networking is broken.

Current handling:

- Treat macvlan as validated for outbound container connectivity.
- Treat DSM host-to-container reachability as requiring a separate design.
- Use an external LAN client for service reachability tests, or generate a
  reviewable host-side macvlan shim plan with
  `scripts/plan-macvlan-host-shim.sh` if DSM itself must reach the container.
