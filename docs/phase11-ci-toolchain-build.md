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

Synology's CPU/package architecture list identifies the DS224+ as x86_64 with
package architecture `Geminilake`. The first external build target should
therefore use the DSM 7.3 `geminilake` x86_64 toolchain/platform family.

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
2. In the first workflow version, record the selected Synology toolchain URLs
   and optionally download the toolchain/toolkit tarballs; do not build LXC yet.
3. Add a CI artifact manifest that records toolchain URL, platform, DSM version
   and checksums when downloads are enabled.
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

## Initial workflow

The first workflow is `.github/workflows/toolchain-recon.yml`.

It runs automatically on PR/push with downloads disabled. That gives CI evidence
for the selected platform metadata and URL reachability without pulling large
toolchain archives.
The same workflow is also manually startable with `workflow_dispatch` for the
later download-enabled reconnaissance.

Manual runs accept:

- DSM toolchain version, default `7.3-86009`
- toolkit version, default `7.3`
- platform, default `geminilake`
- toolchain filename, default `geminilake-gcc1220_glibc236_x86_64-GPL.txz`
- `download_toolchain`, default `false`

The pinned archive MD5 values for the first candidate are:

```text
bc93d88359a055b398d8e78965bc95cc  geminilake-gcc1220_glibc236_x86_64-GPL.txz
fd0862fa44189606bd64cc32138f3302  base_env-7.3.txz
cb6221764494afdbec7aa1a22ea3ad6a  ds.geminilake-7.3.dev.txz
ec544e4e943da80f8b18163516c4ba46  ds.geminilake-7.3.env.txz
```

The workflow uses the direct `global.synologydownload.com/download/...` artifact
URLs referenced by the Synology archive index, rather than the archive UI path.

With downloads disabled, it only records the selected URLs and uploads a small
reconnaissance artifact plus HTTP header probes. With downloads enabled, it
downloads the selected toolchain/toolkit tarballs and records checksums. It
still does not build LXC.

GitHub Actions note: a newly added `workflow_dispatch` workflow may not be
startable through the GitHub API until the workflow file exists on the
repository default branch. The automatic PR/push trigger exists so the workflow
can still be validated before that merge.
