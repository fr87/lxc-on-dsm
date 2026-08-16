# Phase 7: narrow root helper prototype

This document defines the first non-installed root helper prototype. The helper
is a policy boundary for the existing package lifecycle scripts; it is not a
general-purpose privileged command runner.

## Prototype and package-tool status

The first prototype lives outside the DSM package payload:

```text
scripts/experimental/lxc-on-dsm-root-helper.sh
```

After successful dry-run and real root validation, the `0.1.0-0010` package gate
also ships the same helper as a normal package tool:

```text
/var/packages/lxc-on-dsm/target/scripts/lxc-on-dsm-root-helper.sh
```

It does not change `conf/privilege`, does not set a setuid bit and is not called
by Package Center for non-root lifecycle execution.

## Allowed contract

The helper accepts only:

```text
start
stop
status
```

The package id is fixed to `lxc-on-dsm`. The profile path must be under:

```text
/var/packages/lxc-on-dsm/etc/
```

The helper rejects:

- arbitrary verbs
- arbitrary command paths
- relative profile paths
- profile paths containing `..`
- container names outside `[A-Za-z0-9_.-]`
- state directories outside `/volumeN/@lxc/lab/containers`
- package ids other than `lxc-on-dsm`

## Execution model

For real execution, the helper requires `uid=0`. It then delegates to fixed,
installed package scripts:

```text
/var/packages/lxc-on-dsm/target/scripts/start-macvlan-profile.sh
/var/packages/lxc-on-dsm/target/scripts/stop-macvlan-profile.sh
/var/packages/lxc-on-dsm/target/scripts/doctor-macvlan-profile.sh
```

Logs are written to:

```text
/var/packages/lxc-on-dsm/var/artifacts
```

The helper deliberately does not accept a script path from the caller.

## Dry-run gate

Before any Virtual DSM root test, inspect the command decision without starting
or stopping anything:

```sh
sh scripts/experimental/lxc-on-dsm-root-helper.sh --dry-run start --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh scripts/experimental/lxc-on-dsm-root-helper.sh --dry-run stop --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh scripts/experimental/lxc-on-dsm-root-helper.sh --dry-run status --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
```

Expected result:

```text
Result: ROOT HELPER DRY RUN COMPLETE. No lifecycle action was executed.
```

## Real root test gate

Only after reviewing the dry-run output in Virtual DSM, run as root:

```sh
sh scripts/experimental/lxc-on-dsm-root-helper.sh status --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh scripts/experimental/lxc-on-dsm-root-helper.sh start --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh scripts/experimental/lxc-on-dsm-root-helper.sh status --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh scripts/experimental/lxc-on-dsm-root-helper.sh stop --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh scripts/experimental/lxc-on-dsm-root-helper.sh status --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
```

The expected post-stop state is unchanged from Phase 5: container stopped, no
lifecycle runtime state, no shim and no lifecycle route.

## Validated Virtual DSM result

The first real root helper test succeeded in Virtual DSM:

```text
helper status before start:
container_state=STOPPED
runtime_state_present=NO
shim_present=NO
route_present=NO_RUNTIME_IP
Result: MACVLAN DOCTOR PASS

helper start:
container_ip=10.26.88.217
gateway=10.26.88.199
dhcp_status=OK
shim_created=1
route_added=1
Result: MACVLAN LIFECYCLE STARTED

helper status while running:
container_state=RUNNING
runtime_state_present=YES
runtime_container_ip=10.26.88.217
runtime_dhcp_status=OK
runtime_shim_created=1
runtime_route_added=1
shim_present=YES
route_present=YES
Result: MACVLAN DOCTOR PASS

helper stop:
container_stopped=YES
shim_absent=YES
Result: MACVLAN LIFECYCLE STOPPED

helper status after stop:
container_state=STOPPED
runtime_state_present=NO
shim_present=NO
route_present=NO_RUNTIME_IP
Result: MACVLAN DOCTOR PASS
```

This validates the helper as a policy gate for explicit root execution. It does
not yet validate Package Center delegation or helper installation.

## Package Center handoff

Package Center `start` still must not run privileged lifecycle actions as the
package user. In `0.1.0-0010`, the Package Center wrapper may point an
administrator at the installed helper path, but non-root `start`/`stop` remains
blocked.

Generate the handoff plan:

```sh
sh scripts/plan-helper-handoff.sh
```

Expected result:

```text
Result: HELPER HANDOFF PLAN GENERATED. No DSM package was changed.
```

## `0.1.0-0010` package-tool gate

The accepted handoff option is to ship the helper as a normal package file,
while still requiring explicit root execution:

```text
target/scripts/lxc-on-dsm-root-helper.sh
```

Archive checks must prove:

- the helper is present in `package.tgz`
- the helper has an executable non-setuid mode
- Package Center `start`/`stop` still explain the root lifecycle gate
- the wrapper points to the installed helper path for manual root use

After installing `0.1.0-0010`, validate manually:

```sh
sh /var/packages/lxc-on-dsm/target/scripts/lxc-on-dsm-root-helper.sh --dry-run start --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh /var/packages/lxc-on-dsm/target/scripts/lxc-on-dsm-root-helper.sh status --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh /var/packages/lxc-on-dsm/target/scripts/lxc-on-dsm-root-helper.sh start --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh /var/packages/lxc-on-dsm/target/scripts/lxc-on-dsm-root-helper.sh stop --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
sh /var/packages/lxc-on-dsm/target/scripts/lxc-on-dsm-root-helper.sh status --profile /var/packages/lxc-on-dsm/etc/lab-macvlan.env
```
