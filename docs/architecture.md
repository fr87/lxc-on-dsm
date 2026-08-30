# Architecture direction

Project-owned state must remain separate from DSM-owned files. The provisional layout is:

```text
/var/packages/<package>/target/   application payload
/var/packages/<package>/etc/      generated configuration
/volumeN/@lxc/                    container rootfs and persistent state
```

Exact locations remain open until Phase 1. Builds will pin versions and checksums and must not replace DSM libc, init, Container Manager, or networking configuration. Binaries, configuration, and container data remain independently recoverable.

## Phase layout

```text
scripts/analyze-dsm.sh       collect read-only host evidence
scripts/compare-reports.sh   compare hardware and Virtual DSM reports
scripts/evaluate-report.sh   turn one report into a preflight decision
config/lxc/                  project-owned LXC defaults
config/lab-macvlan.env       local lab lifecycle profile, generated on DSM
spk/                         DSM package skeleton templates, not installable yet
artifacts/                   local reports, not committed by default
```

Lifecycle scripts should read project-owned profiles instead of hard-coding DSM
state. Generated profiles are intentionally small and reviewable so they can be
recreated after DSM updates.

## DSM package privilege boundary

The current package architecture is split deliberately:

- the installable SPK remains a low-privilege DSM 7 package
- package `status` is a management/doctor operation
- Package Center `start`/`stop` block until a reviewed privileged boundary
  exists
- explicit root execution of the installed package wrapper is the validated lab
  lifecycle fallback

Phase 7 investigates whether the privileged lifecycle can be mapped to a
documented DSM Resource Worker. If not, any future helper must be narrow,
auditable and limited to reviewed lifecycle verbs rather than exposing a generic
root execution path.

## Build versus runtime boundary

Build tools must stay outside the physical NAS runtime package. The final
hardware package should contain an already-built LXC runtime plus lifecycle and
diagnostic scripts; it must not install Entware and must not carry compilers,
Meson, Ninja, pkg-config, source trees or build intermediates.

See `docs/phase10-runtime-packaging.md` for the current packaging rule.
