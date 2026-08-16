# Phase 9: hardware lab candidate

Phase 9 prepares the first cautious DS224+ hardware lab candidate.

The important boundary: `0.1.0-0010` is a management/helper SPK. It does not
yet install the LXC userspace itself. The hardware NAS therefore needs a
validated LXC runtime prefix before the package can start a container.

Important hardware finding: the first Virtual DSM runtime bundle was built with
the Entware toolchain and its LXC binaries use the ELF interpreter
`/opt/lib/ld-linux-x86-64.so.2`. That is acceptable inside the Virtual DSM lab
where Entware was installed manually, but it is not acceptable for the physical
DS224+ target if Entware must not be installed there. The hardware path is
therefore blocked until the runtime is rebuilt as DSM-native or otherwise made
independent from an Entware `/opt` interpreter.

Generate the plan for that next runtime path with:

```sh
sh scripts/plan-dsm-native-runtime.sh
```

## LXC runtime bundle gate

Create a portable runtime bundle from the validated Virtual DSM prefix:

```sh
sh scripts/create-lxc-runtime-bundle.sh --prefix /volume1/@lxc/lab/opt
```

Expected result:

```text
Result: LXC RUNTIME BUNDLE CREATED. No container or network state was changed.
```

Validate the bundle:

```sh
sh scripts/check-lxc-runtime-bundle.sh artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz
```

Expected result:

```text
Result: LXC RUNTIME BUNDLE CHECK PASS. No install action was performed.
```

The runtime bundle contains only the LXC prefix, such as `bin/`, `lib/` and
`share/`. It must not contain container state, rootfs data or SPK artifacts.

On the hardware NAS, restore the runtime bundle in two steps. First run the
restore gate in dry-run mode:

```sh
sh scripts/restore-lxc-runtime-bundle.sh --bundle artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz --target /volume1/@lxc/lab/opt
```

Expected result:

```text
Result: LXC RUNTIME RESTORE DRY RUN PASS. No runtime files were installed.
```

Only if the target prefix is absent or empty, install explicitly:

```sh
sh scripts/restore-lxc-runtime-bundle.sh --bundle artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz --target /volume1/@lxc/lab/opt --install
```

Expected result:

```text
Result: LXC RUNTIME RESTORED. No container or network state was changed.
```

After any restore, run the host dependency gate before trying `lxc-start` or
installing/starting the SPK lifecycle:

```sh
sh scripts/check-lxc-runtime-deps.sh --prefix /volume1/@lxc/lab/opt
```

If the result reports an `/opt` interpreter on the physical NAS, do not proceed
to container creation. That runtime is a Virtual DSM/Entware lab artifact, not a
hardware-ready runtime.

Validated Virtual DSM evidence:

- `artifacts/lxc-runtime-bundle-20260816T115837Z.tar.gz`
- size: approximately 12 MiB
- required LXC tools present with executable mode bits
- `liblxc` present
- checksum verification passed
- no container state/rootfs data detected
- no SPK artifact detected
- restore gate validated the bundle and refused to overwrite the existing
  non-empty Virtual DSM prefix `/volume1/@lxc/lab/opt`
- later physical DS224+ probing showed the restored runtime expects
  `/opt/lib/ld-linux-x86-64.so.2`; with the project decision to avoid Entware on
  the physical NAS, this bundle is not hardware-ready

## Hardware handoff bundle

After the SPK and LXC runtime bundle have both passed their gates, create one
portable handoff archive for the physical NAS:

```sh
sh scripts/create-hardware-handoff-bundle.sh \
  --spk build/spk/lxc-on-dsm-0.1.0-0010.spk \
  --runtime-bundle artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz
```

Validate it before copying it to the hardware NAS:

```sh
sh scripts/check-hardware-handoff-bundle.sh artifacts/hardware-handoff-lxc-on-dsm-YYYYMMDDTHHMMSSZ.tar.gz
```

Expected result:

```text
Result: HARDWARE HANDOFF BUNDLE CHECK PASS. No install or restore action was performed.
```

The handoff bundle contains the SPK, the runtime bundle, the read-only DSM
analysis tools, the runtime restore gate, the recovery gates and the Phase 9
runbook. It is still inert: unpacking or checking it must not install packages,
restore runtime files, start containers or change networking.

Validated Virtual DSM handoff evidence:

- `artifacts/hardware-handoff-lxc-on-dsm-20260816T121036Z.tar.gz`
- size: approximately 12 MiB
- exactly one SPK present
- exactly one LXC runtime bundle present
- embedded runtime bundle lists `lxc-start`, `lxc-stop` and runtime libraries
- no container state directories detected
- checksum verification passed

## Hardware candidate order

The first real DS224+ test should be gated in this order:

1. Create and verify a Virtual DSM recovery bundle.
2. Create and verify a Virtual DSM LXC runtime bundle.
3. Create and verify a hardware handoff bundle.
4. Copy the handoff bundle to the physical NAS and unpack it in a lab directory.
5. Run `scripts/analyze-dsm.sh` on the physical NAS.
6. Compare the physical NAS report with the Virtual DSM report.
7. Dry-run the LXC runtime bundle restore on the physical NAS.
8. Install or restore the LXC runtime prefix on the physical NAS only after the
   report comparison and restore dry-run are acceptable.
9. Run `scripts/check-lxc-runtime-deps.sh --prefix /volume1/@lxc/lab/opt`.
10. Continue only if the restored runtime does not require the Entware
    `/opt/lib/ld-linux-x86-64.so.2` interpreter.
11. Install `lxc-on-dsm-0.1.0-0010.spk` on the physical NAS.
12. Run `scripts/check-package-recovery.sh`.
13. Run the installed helper with `--dry-run`.
14. Create a hardware recovery bundle.
15. Only then consider a single macvlan lifecycle start/stop test.

Package Center `start` remains intentionally blocked for the package user.
