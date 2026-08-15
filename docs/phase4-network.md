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
list interface names, while route and IPv6 procfs evidence existed. Treat
container-side interface introspection as still under investigation until a
follow-up probe compares `/proc/net/dev` with `ip link` output from inside the
container.

Expected result:

```text
Result: VETH PROBE COMPLETE. No bridge was configured.
```

If the probe reports that the host veth still exists after stop, do not proceed
to bridge testing until the leftover interface has been investigated and
removed.
