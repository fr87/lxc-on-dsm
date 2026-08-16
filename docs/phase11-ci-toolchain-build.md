# Phase 11: CI toolchain build path

Phase 11 moves LXC runtime creation away from all DSM machines.

The physical DS224+ is not a build host. Virtual DSM is not a long-term build
host either. Build tools, source trees and temporary dependencies belong in a
separate CI/build environment. The NAS receives only reviewed runtime/package
artifacts.

## Build location

The preferred build location is GitHub Actions or an equivalent disposable Linux
CI runner.

The CI runner may download and unpack Synology's DSM 7.3 toolchain/build
environment for the target platform, build the LXC userspace, assemble a runtime
bundle and publish that bundle as a CI artifact.

The runner may contain:

- Synology Toolkit / `pkgscripts-ng`
- Synology DSM 7.3 toolchain or Toolkit tarballs
- compilers
- Meson/Ninja
- pkg-config/pkgconf
- source trees
- temporary build directories

The final runtime bundle and SPK must not contain those build-only components.

## Target platform assumption

The DS224+ hardware reconnaissance observed an x86_64 DSM system loader:

```text
/lib64/ld-linux-x86-64.so.2
```

The first external build target should therefore be the DSM 7.3 x86_64
Synology toolchain/platform family that matches the physical DS224+ report.

Before hard-coding a platform value, confirm the platform signal from the
physical NAS report, for example from `uname -a` or Synology model/platform
metadata collected by `scripts/analyze-dsm.sh`.

## CI output contract

A CI runtime build is acceptable only if it produces:

- `artifacts/lxc-runtime-bundle-*.tar.gz`
- a build log
- a manifest with source versions and checksums
- interpreter evidence for LXC binaries
- package-boundary evidence

The CI job must not produce a hardware handoff bundle until the runtime bundle
passes:

```sh
sh scripts/check-lxc-runtime-bundle.sh artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz
sh scripts/check-runtime-package-boundary.sh artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz
```

The physical DS224+ must then still run:

```sh
sh scripts/restore-lxc-runtime-bundle.sh --bundle artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz --target /volume1/@lxc/lab/opt
sh scripts/check-lxc-runtime-deps.sh --prefix /volume1/@lxc/lab/opt
```

## Non-goals

Phase 11 must not:

- require Entware on the physical NAS
- install build tools on the physical NAS
- use the physical NAS as a compiler host
- include source trees in the final SPK
- include compilers, Meson, Ninja, pkg-config/pkgconf or opkg in the final SPK
- start containers during CI

## Initial implementation sequence

1. Add a manual GitHub Actions workflow skeleton.
2. In the first workflow version, download/list the selected Synology toolchain
   only; do not build LXC yet.
3. Add a CI artifact manifest that records toolchain URL, platform, DSM version
   and checksums.
4. Add an LXC configure/build step only after the selected platform has been
   confirmed.
5. Package only the installed runtime prefix into a runtime bundle.
6. Run runtime/package-boundary gates in CI.
7. Download the CI runtime artifact and test only the restore dry-run and
   dependency gates on the physical DS224+.

## Current decision

No further local VM or physical NAS build environment is required. The next
runtime candidate should be produced by CI or an equivalent disposable external
Linux build runner.
