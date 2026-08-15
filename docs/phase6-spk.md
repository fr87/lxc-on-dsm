# Phase 6: DSM package skeleton

Phase 6 starts the transition from lab scripts to a DSM package, but it does
not produce an installable `.spk` yet. The first gate is a reviewable skeleton
that maps DSM package lifecycle hooks to the validated profile lifecycle.

## Current scope

The skeleton under `spk/` is template-only:

- no package is built
- no package is installed
- no DSM package scripts are executed
- no container is started
- no networking is changed

## Guardrails

The package design must keep these constraints:

- package `status` is read-only and calls the doctor
- package `start` calls the profile lifecycle start wrapper
- package `stop` calls the profile lifecycle stop wrapper
- package install and upgrade must not autostart containers
- package upgrade must run compatibility/profile checks before any later start
- package uninstall must not delete container data unless explicitly requested
- DSM production bridges and `eth0` must not be reconfigured

## Skeleton files

```text
spk/INFO.template
spk/scripts/start-stop-status.template
spk/scripts/preinst.template
spk/scripts/postinst.template
spk/scripts/preupgrade.template
spk/scripts/postupgrade.template
spk/scripts/preuninst.template
```

Validate the skeleton:

```sh
sh scripts/check-spk-skeleton.sh
```

Expected result:

```text
Result: SPK SKELETON OK. No package was built or installed.
```

## Proposed DSM lifecycle mapping

```text
status      -> scripts/doctor-macvlan-profile.sh
start       -> scripts/start-macvlan-profile.sh
stop        -> scripts/stop-macvlan-profile.sh
preupgrade  -> stop managed runtime state
postupgrade -> verify compatibility and profile, keep autostart disabled
preuninst   -> stop managed runtime state, preserve data by default
```

The next packaging gate should create a local build plan that assembles a dry
run payload directory from project-owned files. It should still avoid producing
or installing an `.spk` until the payload layout has been reviewed.

## Validated skeleton gate

Validated in Virtual DSM:

```text
Result: SPK SKELETON OK. No package was built or installed.
```

## Dry-run payload assembly

Assemble a local review tree under `build/`:

```sh
sh scripts/assemble-spk-payload.sh
```

Expected result:

```text
Result: SPK PAYLOAD ASSEMBLED. No .spk was built or installed.
```

Then validate the assembled tree:

```sh
sh scripts/check-spk-payload.sh
```

Expected result:

```text
Result: SPK PAYLOAD OK. No .spk was built or installed.
```

This dry-run tree is intentionally ignored by Git and must be reviewed before
adding a real `.spk` builder.

Validated in Virtual DSM:

```text
Result: SPK PAYLOAD ASSEMBLED. No .spk was built or installed.
Result: SPK PAYLOAD OK. No .spk was built or installed.
```

## Build plan

Generate a reviewable build plan before adding a real SPK builder:

```sh
sh scripts/plan-spk-build.sh
```

Expected result:

```text
Result: SPK BUILD PLAN GENERATED. No .spk was built or installed.
```

The build plan records the intended archive layout and future manual commands,
but deliberately does not create an `.spk`.

## Experimental SPK archive build

Only after the skeleton, payload and build-plan gates pass, build a local SPK
archive:

```sh
sh scripts/build-spk.sh
```

Expected result:

```text
Result: SPK BUILT. No package was installed and no package scripts were executed.
```

Then inspect the archive before any install attempt:

```sh
sh scripts/check-spk-archive.sh --spk build/spk/lxc-on-dsm-0.1.0-lab.spk
```

Expected result:

```text
Result: SPK ARCHIVE OK. No package was installed and no package scripts were executed.
```

This gate creates a local `.spk` artifact under `build/`, which is ignored by
Git. It still does not install the package and does not execute any package
script.

Validated in Virtual DSM:

```text
Result: SPK BUILT. No package was installed and no package scripts were executed.
Result: SPK ARCHIVE OK. No package was installed and no package scripts were executed.
```

The first local artifact is:

```text
build/spk/lxc-on-dsm-0.1.0-lab.spk
```

The next gate must be an installation plan for Virtual DSM only. It should
include pre-install doctor/status checks, package installation, package status,
package start, package stop, post-stop doctor checks, and uninstall/recovery
notes before any installation is attempted.

## Virtual DSM installation plan

Generate a reviewable install plan before attempting package installation:

```sh
sh scripts/plan-spk-install.sh
```

Expected result:

```text
Result: SPK INSTALL PLAN GENERATED. No package was installed and no package scripts were executed.
```

The generated plan is intentionally manual and Virtual DSM-only. It includes
pre-install doctor/archive checks, package install options, package-owned
profile placement, package start/stop smoke testing, post-stop doctor checks
and rollback notes.
