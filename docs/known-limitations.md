# Known limitations

This document tracks limitations discovered during the DSM LXC lab work. A
limitation listed here may still be acceptable for the current phase if it is
isolated and reproducible.

## `lxc-attach` fails in the Phase 2 build

Status: open, non-blocking for Phase 3.

Observed in Virtual DSM:

```text
Unsupported config key "lxc.seccomp"
drop_capabilities: Function not implemented
Failed to attach to container
```

Current interpretation:

- LXC was intentionally built with seccomp integration disabled during Phase 2.
- DSM/Entware appears not to provide the capability operation behavior expected
  by LXC attach in this build profile.
- Foreground container start/stop still works and remains the trusted Phase 3
  measurement path.

Current handling:

- `scripts/probe-lab-features.sh` records `lxc-attach` as a warning.
- The probe then collects runtime evidence through foreground start.
- This must be revisited before treating the project as suitable for real
  long-running workloads.

Potential future paths:

- Build a second LXC profile with seccomp support enabled if dependencies are
  feasible on DSM/Entware.
- Investigate whether DSM capability headers or runtime behavior need an LXC
  compatibility patch.
- Keep `lxc-attach` unsupported and design operational tooling around
  foreground/console workflows, if acceptable for the target workloads.
