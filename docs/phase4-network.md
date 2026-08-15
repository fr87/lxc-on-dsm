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
