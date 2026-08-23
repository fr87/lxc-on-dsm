# Phase 10: runtime packaging without build tools

Phase 10 defines the packaging boundary for a hardware-ready LXC runtime.

The physical DS224+ must not install Entware and the final SPK must not contain
or install compiler/build tooling. Build tools are allowed only in a separate
build environment. The packaged NAS artifact should contain the already-built
runtime and the narrow lifecycle/diagnostic scripts needed to operate it.

## Packaging rule

The final package may include:

- LXC runtime binaries and libraries required at execution time
- LXC configuration templates
- lifecycle scripts
- diagnostic and recovery scripts
- package metadata

The final package must not include:

- `gcc`, `g++`, `cc` or `c++`
- `make`
- `meson`
- `ninja`
- `pkg-config` or `pkgconf`
- source trees
- object files or static build intermediates
- Entware package manager state
- an Entware `/opt` dynamic loader dependency

## Build environment rule

The build environment can be dirty and tool-heavy. The NAS package cannot.

Acceptable build locations include:

- a disposable Virtual DSM build VM
- an external Linux build host using a Synology-compatible toolchain
- a CI/build container that produces a reviewed runtime bundle

Given the current project constraint, the physical DS224+ must not be used as a
build host and no additional user-managed VM is required. The preferred next
build location is GitHub Actions or an equivalent disposable external Linux CI
runner. See `docs/phase11-ci-toolchain-build.md`.

The output must pass the runtime gates before it becomes a hardware candidate:

```sh
sh scripts/check-lxc-runtime-bundle.sh artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz
sh scripts/restore-lxc-runtime-bundle.sh --bundle artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz --target /volume1/@lxc/lab/opt
sh scripts/check-lxc-runtime-deps.sh --prefix /volume1/@lxc/lab/opt
```

## Current hardware implication

The Entware-built Virtual DSM runtime remains useful as early proof that LXC
works on DSM when the userspace can run. It is not the final hardware runtime,
because its binaries use `/opt/lib/ld-linux-x86-64.so.2`.

The current release-candidate runtime is produced outside the physical NAS by
GitHub Actions and targets the DSM system loader observed on the hardware:

```text
/lib64/ld-linux-x86-64.so.2
```

Virtual DSM validation on 2026-08-23 replaced the old Entware-built lab runtime
with the packaged CI runtime from run `32652387021`. The old runtime was moved
aside as a recoverable VM-only backup, then the package-owned restore wrapper
installed the bundled runtime into `/volume1/@lxc/lab/opt`. `lxc-start --version`
reported `6.0.6`.

The same Virtual DSM validation created a stopped `alpine-from-spk` container
from the Alpine image embedded in the SPK and ran the netzwerklose smoke test
successfully:

```text
hostname=alpine-from-spk
kernel=4.4.302+
pid1_comm=sh
self_nspid=5
cgroup_mounts=19
net_devices=
Result: SMOKE TEST PASSED. Container was started and stopped without networking.
```

The productive physical DS224+ was not contacted for this validation.

The package now also ships `target/scripts/run-packaged-smoke-test.sh` so the
networkless smoke test can be run from the installed SPK itself. The script
refuses to run unless the selected container is configured with:

```text
lxc.net.0.type = none
lxc.start.auto = 0
```

For the first real LAN usability gate, the package also ships
`target/scripts/run-packaged-macvlan-dhcp-test.sh`. It is dry-run by default and
requires `--run` before it starts a macvlan container. It refuses to run unless
the selected container is configured with:

```text
lxc.net.0.type = macvlan
lxc.start.auto = 0
```

The test uses the configured parent interface only as a macvlan parent. It does
not bridge, readdress or reconfigure the DSM host interface.

The package also ships a persistent explicit start/stop pair:

```sh
sh /var/packages/lxc-on-dsm/target/scripts/start-packaged-container.sh --name alpine-empty
sh /var/packages/lxc-on-dsm/target/scripts/start-packaged-container.sh --name alpine-empty --run
sh /var/packages/lxc-on-dsm/target/scripts/stop-packaged-container.sh --name alpine-empty
```

Persistent `none` starts are intentionally refused. `none` remains a short
smoke-test mode. Persistent package starts currently accept `empty` for isolated
local containers and `macvlan` for DHCP/LAN containers.

Virtual DSM validation on 2026-08-23 installed a local runtime-bundled SPK with
the package-owned macvlan DHCP test, created `alpine-packaged-lan` from the
packaged Alpine image and ran:

```sh
sh /var/packages/lxc-on-dsm/target/scripts/run-packaged-macvlan-dhcp-test.sh \
  --name alpine-packaged-lan \
  --run
```

Evidence:

```text
dhcp_status=OK
addr_after=4: eth0 inet 10.26.88.145/24 ...
gateway=10.26.88.1
gateway_ping=OK
internet_ping=OK
Result: PACKAGED MACVLAN DHCP TEST COMPLETE.
```

The container was stopped after the foreground probe. The productive physical
DS224+ was not contacted.

The same package start/stop path was later validated in Virtual DSM with:

```text
alpine-empty-run: network_type=empty, RUNNING observed, then STOPPED
alpine-macvlan-run: network_type=macvlan, dhcp_status=OK, container_ip=10.26.88.134, RUNNING observed, then STOPPED
```

This validation used only the Virtual DSM lab. The productive physical DS224+
was not contacted.

## Repeatable Virtual DSM validation gate

The manual Virtual DSM sequence is captured by
`scripts/validate-packaged-spk-in-vdsm.sh`. The script is not an unattended
production installer. It requires explicit flags for every mutating phase:

- `--install-package` for `/usr/syno/bin/synopkg install`;
- `--restore-runtime` for restoring the packaged runtime;
- `--backup-existing-runtime` before an existing non-empty runtime prefix is
  moved aside;
- `--create-container` for creating a stopped container from the packaged
  Alpine image;
- `--smoke` for one networkless start/stop smoke test.

Example for a disposable Virtual DSM lab:

```sh
sh scripts/validate-packaged-spk-in-vdsm.sh \
  --spk /volume1/Dev/lxc-on-dsm/build/ci-runtime-spk-32652387021/spk/lxc-on-dsm-0.1.0-0010.spk \
  --container alpine-from-spk-2 \
  --install-package \
  --restore-runtime \
  --backup-existing-runtime \
  --create-container \
  --smoke
```

If the packaged runtime is already restored and should be kept, omit
`--restore-runtime --backup-existing-runtime` and choose a fresh container name.

## Success criteria

A runtime candidate is hardware-packaging ready when:

1. the runtime bundle contains no container state or rootfs data;
2. the runtime bundle contains no SPK artifact;
3. the runtime bundle contains no build tools or source/build intermediates;
4. restored LXC binaries do not request `/opt/lib/ld-linux-x86-64.so.2`;
5. `lxc-start --version` works with only the packaged runtime/library path;
6. no Entware package or `/opt` bootstrap is required on the physical DS224+.
