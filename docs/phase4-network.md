# Phase 4: network probes

Phase 4 is intentionally split into very small gates. The baseline
`alpine-lab` container remains networkless and should not be modified for
network experiments.

## Preflight

Run the read-only preflight first:

```sh
sh scripts/check-network-prereqs.sh
```

This gathers host network tooling and module evidence. It does not start a
container and does not create, remove or reconfigure interfaces.

Expected result:

```text
Result: NETWORK PREFLIGHT COMPLETE. No networking was changed.
```

## Probe order

1. Keep `alpine-lab` as the known-good no-network baseline.
2. Create a separate throwaway network lab container.
3. Test a config with `lxc.net.0.type = empty`.
4. Probe `veth` only after host evidence is acceptable.
5. Evaluate bridge and macvlan as separate opt-in experiments.

Do not attach LXC directly to DSM's production network stack until the earlier
gates have produced reproducible logs and a rollback note.

## Empty network namespace gate

Create a separate network lab container. This reuses the Alpine minirootfs but
does not modify the known-good `alpine-lab` baseline:

```sh
sh scripts/create-netlab-container.sh --prefix /volume1/@lxc/lab/opt --name alpine-netlab
sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name alpine-netlab
```

The generated config contains:

```text
lxc.net.0.type = empty
lxc.start.auto = 0
```

If the config loads, run the foreground probe:

```sh
sh scripts/run-empty-network-probe.sh --prefix /volume1/@lxc/lab/opt --name alpine-netlab
```

Expected result:

```text
Result: EMPTY NETWORK PROBE COMPLETE. No host interface or bridge was configured.
```

This still does not create a veth pair, does not attach a bridge, and does not
change DSM networking.

## Detached veth gate

Only after the empty network namespace gate passes, create a separate veth lab
container. This still does not attach to a bridge:

```sh
sh scripts/create-netlab-container.sh --prefix /volume1/@lxc/lab/opt --name alpine-vethlab --network-type veth --host-veth lxcveth0
sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name alpine-vethlab
```

Then run the veth lifecycle probe:

```sh
sh scripts/run-veth-network-probe.sh --prefix /volume1/@lxc/lab/opt --name alpine-vethlab
```

The probe checks that the host-side veth appears while the detached container is
running and disappears again after stop. It also runs a foreground container
probe to capture container-side network evidence.

Validated in Virtual DSM:

```text
OK: host veth appeared while detached container was running
OK: host veth disappeared after detached stop
OK: host veth absent after foreground probe
```

In the first successful run, `/proc/net/dev` inside the foreground probe did not
list interface names, while route and IPv6 procfs evidence existed. A follow-up
run showed `ip_link_count=3`, so container-side interfaces exist even where the
minimal `/proc/net/dev` parsing is not useful.

Expected result:

```text
Result: VETH PROBE COMPLETE. No bridge was configured.
```

If the probe reports that the host veth still exists after stop, do not proceed
to bridge testing until the leftover interface has been investigated and
removed.

## Bridge preflight

Before creating any bridge-backed container, inspect the DSM bridge landscape:

```sh
sh scripts/check-bridge-prereqs.sh
```

This is read-only. It collects `ip link`, `brctl show` and sysfs bridge/port
evidence where available.

Expected result:

```text
Result: BRIDGE PREFLIGHT COMPLETE. No networking was changed.
```

Do not attach an LXC veth to a DSM production bridge until this report has been
reviewed. Prefer a dedicated throwaway lab bridge for the first bridge
experiment if DSM allows that safely.

## Isolated bridge plan

If bridge preflight shows no DSM bridge or only production interfaces, generate
a manual plan for a dedicated throwaway bridge:

```sh
sh scripts/plan-isolated-bridge-probe.sh
```

This does not change networking. It writes a reviewable command plan under
`artifacts/`.

The planned bridge experiment is intentionally isolated:

- no `eth0`
- no DSM production bridge
- no DHCP
- no IP address
- no route changes
- no firewall changes

Only run the generated commands after reviewing the plan and keeping the VM
snapshot ready. The cleanup section of the generated plan must be run even if
the probe fails.

When `scripts/run-veth-network-probe.sh` sees `lxc.net.0.link` in the container
config, it switches to isolated-bridge reporting. It then checks whether the
host veth appears as a bridge port while the container is running and disappears
again after stop.

If the configured bridge does not exist, the script refuses to start the
container. Recreate the isolated lab bridge from the generated plan first, or
remove `lxc.net.0.link` from the container config to return to detached veth
mode.

Expected bridge-linked result:

```text
Result: ISOLATED BRIDGE PROBE COMPLETE. No production interface was attached.
```

Validated in Virtual DSM:

- isolated bridge creation with `brctl addbr lxcbrlab0`
- bridge-linked veth container config loading
- bridge-linked veth container startup through the probe path
- successful cleanup: `lxcbrlab0` absent after cleanup

The isolated bridge gate is considered complete. Do not proceed from this result
directly to LAN connectivity; production bridge, `eth0`, DHCP, static IP and
firewall/NAT behavior remain separate future gates.
