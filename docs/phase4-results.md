# Phase 4 results: network namespace and isolated bridge gates

Phase 4 has been validated in Virtual DSM through the isolated bridge gate. The
tests intentionally avoided DSM production interfaces and did not connect any
container to the LAN.

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

## Current boundary

The following has not been tested and remains out of scope for this phase:

- attaching LXC veth to `eth0`
- attaching LXC veth to a DSM production bridge
- DHCP from the LAN
- static IP assignment
- route changes
- firewall/NAT rules
- macvlan

The next phase should treat LAN connectivity as a separate opt-in experiment
with an explicit rollback plan.
