# Phase 4 results: network namespace, isolated bridge and macvlan LAN gates

Phase 4 has been validated in Virtual DSM through the macvlan DHCP LAN gate.
The bridge tests intentionally avoided DSM production interfaces. The LAN test
used macvlan on `eth0` without moving the host interface into a bridge.

Validated results:

- The read-only network preflight completed without changes.
- `lxc.net.0.type = empty` starts and stops successfully.
- Detached `veth` lifecycle works without a bridge:
  - host-side veth appears while the container is running
  - host-side veth disappears after stop
  - no host-side veth remains after foreground probing
- A dedicated isolated lab bridge can be created manually with `brctl`.
- A veth-backed container config with `lxc.net.0.link = lxcbrlab0` loads.
- The bridge-linked container starts through the veth probe path.
- After cleanup, the isolated bridge is absent again:

```text
Device "lxcbrlab0" does not exist.
bridge lxcbrlab0 doesn't exist; can't delete it
```

The later repeated bridge-linked probe failed only because the temporary bridge
had already been removed while the container config still referenced it. This is
expected and is now handled by the probe script with a pre-start bridge
existence check.
- Macvlan on `eth0` starts and obtains LAN connectivity:

```text
dhcp_status=OK
addr_after=13: eth0 inet 10.26.88.230/26 brd 10.26.88.255 scope global eth0
routes_after=default via 10.26.88.199 dev eth0  metric 213 |10.26.88.192/26 dev eth0 scope link  src 10.26.88.230 |
gateway=10.26.88.199
gateway_ping=OK
internet_ping=OK
```

This proves DHCP, an IPv4 address, a default route, gateway reachability and
outbound ICMP reachability from inside the container.
- Direct DSM host-to-container reachability over the macvlan parent interface
  fails without an additional host-side macvlan shim:

```text
dhcp_status=OK
ip_plain=10.26.88.237
gateway=10.26.88.199
host_ping=FAIL
```

This is expected macvlan behavior on Linux-style networking and does not
invalidate the outbound LAN result.

## Current boundary

The following has not been tested and remains out of scope for this phase:

- attaching LXC veth to `eth0`
- attaching LXC veth to a DSM production bridge
- static IP assignment
- host-managed route changes
- firewall/NAT rules
- host-side macvlan shim for DSM host-to-container connectivity
- long-running LAN container behavior

Use `scripts/plan-macvlan-host-shim.sh` to generate a reviewable manual plan if
DSM host-to-container access is required by the target workloads.
