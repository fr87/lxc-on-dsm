# Phase 7: privileged DSM lifecycle gate

Phase 7 investigates the correct DSM 7 boundary for privileged lifecycle
operations. It does not replace the validated `0.1.0-0009` package gate.

## Why this phase exists

The current package boundary is intentionally conservative:

- `0.1.0-0009` installs successfully in Virtual DSM
- package `status` can be used as a low-privilege management check
- Package Center `start`/`stop` fail fast instead of attempting partial LXC
  startup as the package user
- explicit root execution of the installed wrapper starts and stops the
  macvlan lifecycle successfully

This split is expected on DSM 7. Synology moved packages toward lower
privilege execution, and privileged behavior must be designed explicitly rather
than smuggled through broad package metadata.

## Validated boundary

Validated in Virtual DSM:

```text
synopkg install build/spk/lxc-on-dsm-0.1.0-0009.spk
success=true

synopkg start lxc-on-dsm
start_failed
```

The same installed package wrapper works when deliberately executed as root:

```text
sh /var/packages/lxc-on-dsm/scripts/start-stop-status start
dhcp_status=OK
shim_created=1
route_added=1

sh /var/packages/lxc-on-dsm/scripts/start-stop-status stop
container_stopped=YES
shim_absent=YES
```

The package-user failure is also understood: LXC needs privileged access for
rootfs pinning, legacy cgroup handling and network interface setup. Running
those operations as `lxc_on_dsm` fails before a useful container lifecycle can
be established.

## Design options

| Option | Interpretation | Current decision |
| --- | --- | --- |
| Development token / root package | Synology-documented path for privileged packages, but tied to Synology partner/developer approval and a NAS-specific token. | Not the default path for this public lab repository. |
| DSM Resource Worker | DSM-supported model for selected privileged resource operations from low-privilege packages. | Investigate first. Preferred if a suitable official resource exists. |
| Narrow root helper | A small audited helper installed or enabled by the administrator. | Feasible for lab use, but requires a separate review gate. |
| Manual root wrapper | Current validated workaround using installed package scripts. | Keep as the stable fallback until a better privileged boundary is proven. |

## Resource Worker questions

Before adding any `conf/resource` or helper code, answer these questions in the
Virtual DSM lab:

1. Which official DSM Resource Workers are available on this DSM version?
2. Can any built-in worker safely cover the required operations: LXC startup,
   cgroup access, rootfs handling, `ip link` macvlan shim creation, route add
   and cleanup?
3. Does the worker model support start/stop lifecycle operations, or only
   static resource acquisition/update during package install and upgrade?
4. Can the package stay installable without a Synology development token?

If there is no concrete official worker that covers the lifecycle need, the
project should not invent a fake `conf/resource` entry. The next acceptable
experiment would be a separate narrow helper design.

## Helper safety contract

If Phase 7 reaches a helper prototype later, it must be deliberately small:

- no generic root shell
- no arbitrary command execution
- no user-provided executable path
- allowed actions limited to reviewed lifecycle verbs, initially `start`,
  `stop` and possibly `doctor`
- profile path restricted to the package configuration area
- state paths restricted to the reviewed `/volumeN/@lxc/lab` layout
- container names validated with a tight name pattern
- parent interface and shim interface taken from a reviewed profile
- cleanup-first and idempotent stop behavior
- auditable logs under `/var/packages/lxc-on-dsm/var/artifacts`
- Package Center autostart disabled until a full recovery path is validated

The helper must fail closed. If validation is incomplete, it should do nothing.

## Phase 7 gate

Generate the read-only reconnaissance plan:

```sh
sh scripts/plan-resource-worker.sh
```

Expected result:

```text
Result: RESOURCE WORKER PLAN GENERATED. No DSM package was changed.
```

The generated plan is meant to be reviewed and then executed manually in the
Virtual DSM lab. It must not modify package metadata, start containers, create
interfaces or call `synopkghelper update`.

## Virtual DSM reconnaissance result

The first Virtual DSM reconnaissance run showed:

```text
synopkg status lxc-on-dsm
status=start_failed

/var/packages/lxc-on-dsm/conf/privilege
run-as=package
username=lxc_on_dsm
groupname=lxc_on_dsm

/var/packages/lxc-on-dsm/conf/resource
{"systemd-unit":{}}

/usr/syno/sbin/synopkghelper --help
update <package> <resource-id>
update-all-package <resource-id>
```

Current interpretation:

- The installed package has only the default `systemd-unit` resource state.
- `synopkghelper` exposes update entry points, but no direct lifecycle helper
  surface for LXC rootfs, cgroup or macvlan operations.
- No concrete built-in Resource Worker has been identified that maps to the
  required LXC lifecycle.
- The project should not add a speculative `conf/resource` entry without a
  matching documented worker.

This moves the next lab gate to a narrow helper design, while keeping manual
root lifecycle as the known-good fallback.

Generate the helper plan:

```sh
sh scripts/plan-root-helper.sh
```

Expected result:

```text
Result: ROOT HELPER PLAN GENERATED. No DSM package was changed.
```

## Handoff

Phase 7 is complete only when one of these outcomes is documented:

- a concrete official DSM Resource Worker path is identified and gated, or
- no suitable worker exists and a narrow root-helper design is explicitly
  accepted for lab-only testing, or
- the project intentionally keeps manual root lifecycle as the supported
  experimental mode.
