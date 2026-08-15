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

## Manual lifecycle start

After the profile verifies, start the lab container through the profile:

```sh
sh scripts/start-macvlan-profile.sh --profile config/lab-macvlan.env
```

The start script:

- starts the container detached
- obtains DHCP inside the container
- records container IP evidence
- creates a host-side macvlan shim only if `LXC_LAB_HOST_SHIM_CIDR` is set
- refuses to create a shim if the shim IP equals the detected container IP
- adds a `/32` host route only for the detected container IP
- writes runtime ownership state to the container directory

Expected result:

```text
Result: MACVLAN LIFECYCLE STARTED. Stop with scripts/stop-macvlan-profile.sh.
```

## Manual lifecycle stop

Stop and clean up through the same profile:

```sh
sh scripts/stop-macvlan-profile.sh --profile config/lab-macvlan.env
```

The stop script:

- removes the lifecycle-owned `/32` route
- removes the lifecycle-owned shim interface
- stops the container
- archives the runtime state file

Expected result:

```text
Result: MACVLAN LIFECYCLE STOPPED. Container stopped and lifecycle-owned shim removed.
```

If a shim interface exists but no runtime state claims ownership, the stop
script warns instead of deleting an unknown interface. In that case, inspect
the host manually before continuing.

## Doctor / status check

Inspect profile and runtime state without changing anything:

```sh
sh scripts/doctor-macvlan-profile.sh --profile config/lab-macvlan.env
```

The doctor checks:

- profile and LXC binary presence
- container config and rootfs presence
- parent interface presence
- current LXC state
- lifecycle runtime-state file
- effective shim interface presence
- `/32` route presence for the runtime container IP
- stale or orphaned lifecycle state

Expected clean result:

```text
Result: MACVLAN DOCTOR PASS. No container was started and no networking was changed.
```

If it finds a running container without runtime state, a stale runtime-state
file, an orphaned shim or a missing lifecycle route, it returns non-zero and
prints a `PROBLEM:` line. Run the stop script only when the lifecycle state
claims ownership of the shim; otherwise inspect manually.

## Package-user access preparation

When the lifecycle is driven through an installed DSM package, the package user
must be able to traverse the lab container directory and read the LXC config.
The access-prep script is conservative and dry-run by default:

```sh
sh scripts/prepare-package-access.sh \
  --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env \
  --user lxc_on_dsm
```

It only plans these changes:

```text
chmod 0711 LXC_LAB_STATE_DIR
chmod 0711 LXC_LAB_STATE_DIR/LXC_LAB_CONTAINER
chmod 0644 LXC_LAB_STATE_DIR/LXC_LAB_CONTAINER/config
```

Apply explicitly only after reviewing the plan:

```sh
sh scripts/prepare-package-access.sh \
  --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env \
  --user lxc_on_dsm \
  --apply
```

The script does not recurse into the container rootfs and does not change
networking or start containers.

## Validated lifecycle result

Validated in Virtual DSM:

```text
# start
container=alpine-macvlanlab
parent_if=eth0
shim_if=lxcshim0
host_cidr=10.26.88.237/26
container_ip=10.26.88.202
gateway=10.26.88.199
dhcp_status=OK
shim_created=1
route_added=1
runtime_state=/volume1/@lxc/lab/containers/alpine-macvlanlab/lifecycle-state.env

# stop
container=alpine-macvlanlab
shim_if=lxcshim0
container_stopped=YES
shim_absent=YES
```

Result:

```text
MACVLAN LIFECYCLE STARTED
MACVLAN LIFECYCLE STOPPED
```

This validates the manual lifecycle gate:

- profile-driven container start
- DHCP inside the container
- temporary host-side macvlan shim creation
- `/32` route creation for the detected container IP
- runtime ownership state writing
- container stop
- lifecycle-owned shim removal
- post-stop doctor status check

The current boundary remains deliberate: no DSM package integration, no DSM
boot integration and no automatic autostart yet.

Validated post-stop doctor result:

```text
container_state=STOPPED
runtime_state_present=NO
runtime_container_ip=
runtime_shim_created=0
runtime_route_added=0
shim_present=NO
route_present=NO_RUNTIME_IP

Result: MACVLAN DOCTOR PASS. No container was started and no networking was changed.
```
