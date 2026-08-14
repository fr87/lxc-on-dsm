# Phase 3: first stopped lab container

Phase 3 creates the first container definition and root filesystem, but still does not start it automatically. The initial container is deliberately isolated:

- Alpine minirootfs `3.24.1`
- no network: `lxc.net.0.type = none`
- no autostart: `lxc.start.auto = 0`
- project-owned state under `/volume1/@lxc/lab/containers`

## Prepare rootfs and config

```sh
eval "$(sh scripts/print-lxc-env.sh --prefix /volume1/@lxc/lab/opt)"
sh scripts/fetch-sources.sh --output /volume1/Dev/lxc-on-dsm/build/sources
sh scripts/create-lab-container.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
```

The create step unpacks the Alpine minirootfs and writes the LXC config. It does not call `lxc-start`.

The generated config intentionally does not include LXC's installed
`common.conf`. On DSM/Entware this file may reference capability names such as
`mac_admin` and `mac_override` that the lab build cannot parse.

If an older generated config already exists, repair it without deleting the
rootfs:

```sh
sh scripts/repair-lab-config.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
```

## First manual start gate

Only after reviewing the generated config, the first manual start attempt should use foreground mode and immediate shutdown-oriented command selection. No networking should be enabled for the first attempt.

Expected first command, after explicit review:

```sh
lxc-start -F -P /volume1/@lxc/lab/containers -n alpine-lab
```

Do not enable autostart or bridge networking during this phase.

## Reproducible smoke test

After the first manual shell start has succeeded once, use the smoke test for
repeatability:

```sh
sh scripts/run-lab-smoke-test.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
```

The smoke test starts the container in foreground mode, feeds a small command
sequence to `/bin/sh`, records evidence under `artifacts/`, and exits the shell
again. It still keeps the container networkless and does not enable autostart.

Expected result:

```text
Result: SMOKE TEST PASSED. Container was started and stopped without networking.
```

## Feature probe

After the smoke test passes, collect a broader runtime snapshot:

```sh
sh scripts/probe-lab-features.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
```

This starts the container with a temporary keeper command, uses `lxc-attach` to
inspect the running container, then stops it again. It records:

- `lxc-attach` functionality
- hostname and kernel evidence
- PID namespace evidence from `/proc`
- `/proc`, `/sys`, cgroup and `/dev/pts` mount evidence
- capability fields from `/proc/self/status`
- network device visibility while networking is still disabled

Expected result:

```text
Result: FEATURE PROBE COMPLETE. Container was stopped and networking remained disabled.
```
