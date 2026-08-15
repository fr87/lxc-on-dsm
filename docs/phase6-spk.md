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
