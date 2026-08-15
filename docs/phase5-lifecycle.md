# Phase 5: reproducible lab lifecycle

Phase 5 turns the successful macvlan probes into a small, reviewable lifecycle
profile. The first gate is intentionally conservative: write a local profile
and verify that it matches the installed LXC prefix, container config and host
network assumptions.

No container is started by this gate, and no networking is changed.

## Write a local macvlan profile

Create a local profile on the Virtual DSM lab system:

```sh
sh scripts/write-macvlan-profile.sh \
  --prefix /volume1/@lxc/lab/opt \
  --name alpine-macvlanlab \
  --parent-if eth0 \
  --host-cidr FREE_LAN_IP/CIDR
```

The default output is:

```text
config/lab-macvlan.env
```

`FREE_LAN_IP/CIDR` must be a free address in the same LAN as the macvlan
container. Prefer a DHCP reservation or an address outside the DHCP pool. Do
not reuse the current container DHCP address.

If DSM host-to-container access is not needed yet, omit `--host-cidr`. The
profile will still verify with a warning, but host-shim lifecycle steps remain
disabled until a shim address is configured.

## Verify the profile

Run:

```sh
sh scripts/verify-macvlan-profile.sh --profile config/lab-macvlan.env
```

Expected result:

```text
Result: MACVLAN PROFILE VERIFIED. No container was started and no networking was changed.
```

Warnings are acceptable while the profile is still incomplete. Failures must be
fixed before adding start/stop automation.

The verifier checks:

- LXC binaries exist under the configured prefix
- the container config and rootfs exist
- the container is configured for macvlan
- the parent interface matches the profile
- `lxc.start.auto = 0` remains present
- the parent interface exists
- the shim interface is absent before lifecycle use
- the host shim CIDR is configured when host-to-container access is required

## Why this gate exists

DSM updates can alter kernel behavior, paths, package state or network
assumptions. A small project-owned profile gives later repair scripts one
source of truth without modifying DSM-owned configuration.

The next lifecycle gate should add explicit start/stop scripts that consume
this profile and remain reversible:

- start the macvlan lab container
- optionally create the host-side macvlan shim
- write runtime evidence under `artifacts/`
- stop the container
- remove the shim and route
