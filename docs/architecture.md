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
