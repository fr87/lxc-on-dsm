# Phase 9: hardware lab candidate

Phase 9 prepares the first cautious DS224+ hardware lab candidate.

The important boundary: `0.1.0-0010` is a management/helper SPK. It does not
yet install the LXC userspace itself. The hardware NAS therefore needs a
validated LXC runtime prefix before the package can start a container.

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

Validated Virtual DSM evidence:

- `artifacts/lxc-runtime-bundle-20260816T115837Z.tar.gz`
- size: approximately 12 MiB
- required LXC tools present with executable mode bits
- `liblxc` present
- checksum verification passed
- no container state/rootfs data detected
- no SPK artifact detected

## Hardware candidate order

The first real DS224+ test should be gated in this order:

1. Create and verify a Virtual DSM recovery bundle.
2. Create and verify a Virtual DSM LXC runtime bundle.
3. Run `scripts/analyze-dsm.sh` on the physical NAS.
4. Compare the physical NAS report with the Virtual DSM report.
5. Install or restore the LXC runtime prefix on the physical NAS only after the
   report comparison is acceptable.
6. Install `lxc-on-dsm-0.1.0-0010.spk` on the physical NAS.
7. Run `scripts/check-package-recovery.sh`.
8. Run the installed helper with `--dry-run`.
9. Create a hardware recovery bundle.
10. Only then consider a single macvlan lifecycle start/stop test.

Package Center `start` remains intentionally blocked for the package user.
