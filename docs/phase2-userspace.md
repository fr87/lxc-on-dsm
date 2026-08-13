# Phase 2: userspace build baseline

Phase 1 shows matching DS224+ and Virtual DSM runtime evidence for namespaces and base cgroups. Phase 2 therefore starts in Virtual DSM with source fetching and build prerequisite checks only. It does not start containers, enable autostart, change DSM networking or write to DSM system paths.

## Version baseline

The pinned starting point is:

- LXC `6.0.6`
- LXCFS `6.0.6`

LXC 6.0.x is a long-term stable branch supported until June 2029. LXCFS 6.0.x is also supported until June 2029. LXCFS 7.0 is not the default baseline because it removed Cgroup v1 support, while the current DSM reports expose classic cgroup controllers.

## First commands in Virtual DSM

```sh
sh scripts/check-phase2-prereqs.sh
sh scripts/fetch-sources.sh --output /volume1/Dev/lxc-on-dsm/build/sources
sh scripts/build-pkgconf.sh --prefix /opt --install
sh scripts/build-lxc.sh --prefix /volume1/@lxc/lab/opt
```

The fetch step writes only below the selected output directory. The manifest intentionally keeps SHA256 values as `TODO` until the first fetch has been verified against GPG signatures or another trusted checksum source.
The build step compiles LXC under `build/work` and does not install unless `--install` is passed explicitly.

If `check-phase2-prereqs.sh` reports missing build tools, follow the [Entware build toolchain notes](entware-build-toolchain.md) in Virtual DSM.
For a concrete command plan, run `sh scripts/plan-entware-bootstrap.sh --volume /volume1`.

## Build isolation target

The first install prefix should be project-owned and disposable, for example:

```text
/volume1/@lxc/lab/opt
```

Do not install into `/usr`, `/lib`, `/bin`, `/etc`, DSM package directories, or Container Manager paths during Phase 2.

## Gate before first container start

Before any `lxc-start` attempt, the project still needs:

- a successful LXC build under a project-owned prefix
- documented dynamic library paths
- a minimal default config generated from `config/lxc/default.conf.example`
- an explicit decision on privileged versus unprivileged PoC
- a networking decision, initially likely `none` or an isolated bridge in Virtual DSM

## Source references

- LXC downloads and long-term branches: https://linuxcontainers.org/lxc/downloads/
- LXC 6.0.6 release notes: https://linuxcontainers.org/lxc/news/
- LXCFS 6.0.6 release notes: https://discuss.linuxcontainers.org/t/lxcfs-6-0-6-lts-has-been-released/26263
- LXCFS 7.0 Cgroup v1 removal: https://discuss.linuxcontainers.org/t/lxcfs-7-0-lts-has-been-released/26607
