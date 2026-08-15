# Experimental Synology package skeleton

This directory contains a reviewable DSM package skeleton for the lab lifecycle.
It is an experimental `.spk` skeleton, not a production-ready package yet.

Current intent:

- keep package payload separate from DSM-owned files
- wrap the validated profile lifecycle scripts
- keep DSM autostart disabled until explicit package integration gates pass
- make status/doctor read-only
- avoid DSM production bridge changes

The package skeleton currently maps DSM package lifecycle concepts to project
scripts, but packaging, signing, installation and upgrade handling are still
future gates.

DSM 7 package validation requires a package privilege declaration. The skeleton
therefore includes `conf/privilege` with `run-as: package`. That keeps the
package conservative, but it also means privileged LXC and network lifecycle
operations may need a later, explicit privilege/service design before Package
Center `start` can be expected to work end-to-end.

## Proposed package paths

```text
/var/packages/lxc-on-dsm/target/       package payload and wrappers
/var/packages/lxc-on-dsm/etc/          package-owned generated configuration
/volume1/@lxc/                         container data and runtime state
```

## Lifecycle mapping

```text
status      -> scripts/doctor-macvlan-profile.sh
start       -> scripts/start-macvlan-profile.sh
stop        -> scripts/stop-macvlan-profile.sh
preupgrade  -> stop, then preserve package-owned config
postupgrade -> verify profile and compatibility; do not autostart
preuninst   -> stop managed runtime state
postuninst  -> preserve data by default
```

`status` must remain read-only. `postupgrade` must not start containers until
the compatibility gate has been reviewed.
