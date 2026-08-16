# Phase 8: recovery and repair readiness

Phase 8 verifies that the installed package remains understandable and
recoverable after package repair, reinstall-like upgrades or DSM-update-style
state drift.

The first gate is read-only:

```sh
sh scripts/check-package-recovery.sh
```

Expected result:

```text
Result: PACKAGE RECOVERY CHECK PASS. No package or runtime state was changed.
```

## What the check verifies

- installed package directory exists
- `/var/packages/lxc-on-dsm/INFO` reports the expected version
- `conf/privilege` still uses `run-as: package`
- no `ctrl-script` or `tool` privilege rewrites are present
- installed helper exists and is executable without setuid/setgid
- Package Center wrapper still explains the root lifecycle gate
- wrapper points to the installed helper
- package profile is readable
- package `etc` and `var` links resolve
- Package Center `startFailed` marker state is recorded from package files
- helper dry-run works
- helper read-only status/doctor works

The check intentionally does not:

- install or repair the package
- start or stop containers
- create or remove interfaces
- add or remove routes
- modify profiles, permissions or package metadata

## Manual repair gate

Only after the read-only check passes and the container is stopped cleanly,
repair/reinstall can be tested in Virtual DSM:

```sh
sh scripts/check-package-recovery.sh
/usr/syno/bin/synopkg install build/spk/lxc-on-dsm-0.1.0-0010.spk
sh scripts/check-package-recovery.sh
sh /var/packages/lxc-on-dsm/target/scripts/lxc-on-dsm-root-helper.sh --dry-run start --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
```

Package Center `start` is still expected to fail fast for the package user.
Manual root lifecycle remains the validated operational path.

## First Virtual DSM result

Validated in Virtual DSM after `0.1.0-0010` install and helper lifecycle tests:

```text
installed_version=0.1.0-0010
helper_mode=-rwxr-xr-x
OK: installed helper is executable without setuid
OK: wrapper explains root lifecycle gate
OK: wrapper points to installed helper
OK: profile is readable
OK: package artifact directory exists
WARN: Package Center startFailed marker is present; this is expected after the root lifecycle gate is tested
Result: ROOT HELPER DRY RUN COMPLETE. No lifecycle action was executed.
Result: MACVLAN DOCTOR PASS. No container was started and no networking was changed.
Result: PACKAGE RECOVERY CHECK PASS WITH 1 WARNING(S). No package or runtime state was changed.
```

The warning is accepted for this gate because Package Center `start` is
intentionally blocked for the package user. The installed helper remains the
validated manual root lifecycle path.

## First repair gate result

Validated in Virtual DSM over SSH:

```text
pre-repair:
Result: PACKAGE RECOVERY CHECK PASS WITH 1 WARNING(S). No package or runtime state was changed.

repair:
/usr/syno/bin/synopkg install build/spk/lxc-on-dsm-0.1.0-0010.spk
action=repair
last_stage=postupgrade
stage=installed_and_stopped
success=true
version=0.1.0-0010

post-repair:
installed_version=0.1.0-0010
OK: installed helper is executable without setuid
OK: Package Center startFailed marker is absent
Result: ROOT HELPER DRY RUN COMPLETE. No lifecycle action was executed.
Result: MACVLAN DOCTOR PASS. No container was started and no networking was changed.
Result: PACKAGE RECOVERY CHECK PASS. No package or runtime state was changed.
```

The repair cleared the previous `startFailed` marker and preserved the installed
helper, profile, package links and clean stopped runtime state.
