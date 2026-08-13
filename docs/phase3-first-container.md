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

## First manual start gate

Only after reviewing the generated config, the first manual start attempt should use foreground mode and immediate shutdown-oriented command selection. No networking should be enabled for the first attempt.

Expected first command, after explicit review:

```sh
lxc-start -F -P /volume1/@lxc/lab/containers -n alpine-lab
```

Do not enable autostart or bridge networking during this phase.
