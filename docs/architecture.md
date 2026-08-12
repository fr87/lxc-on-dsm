# Architecture direction

Project-owned state must remain separate from DSM-owned files. The provisional layout is:

```text
/var/packages/<package>/target/   application payload
/var/packages/<package>/etc/      generated configuration
/volumeN/@lxc/                    container rootfs and persistent state
```

Exact locations remain open until Phase 1. Builds will pin versions and checksums and must not replace DSM libc, init, Container Manager, or networking configuration. Binaries, configuration, and container data remain independently recoverable.
