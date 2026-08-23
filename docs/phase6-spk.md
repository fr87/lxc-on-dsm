# Phase 6: DSM package skeleton

Phase 6 starts the transition from lab scripts to a DSM package. The first
gates are a reviewable skeleton, a dry-run payload, an inspected `.spk` archive
and then a Virtual DSM-only install test.

## Current scope

The skeleton under `spk/` is conservative:

- package build is local and ignored by Git
- package installation is Virtual DSM-only
- package lifecycle start remains a separate gate from package installation
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
- DSM 7 package metadata must stay compatible with Synology validation rules
- DSM 7 `conf/privilege` uses `run-as: package` so the unsigned third-party SPK
  remains installable
- Package Center `start`/`stop` intentionally block until a reviewed Resource
  Worker or root lifecycle design exists

## Skeleton files

```text
spk/INFO.template
spk/conf/privilege.template
spk/scripts/start-stop-status.template
spk/scripts/preinst.template
spk/scripts/postinst.template
spk/scripts/preupgrade.template
spk/scripts/postupgrade.template
spk/scripts/preuninst.template
spk/scripts/postuninst.template
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
postuninst  -> preserve data by default
```

## DSM 7 package validation gate

The package metadata must satisfy DSM 7's early package validation before any
package directory is created under `/var/packages`:

- `version` uses numeric parts only, for example `0.1.0-0009`
- `os_min_ver` is set to `7.0-40000`
- the SPK archive contains top-level `conf/privilege`
- `conf/privilege` declares `"run-as": "package"`
- `conf/privilege` does not use `tool` or `ctrl-script` attribute rewrites

The old local artifact name `lxc-on-dsm-0.1.0-lab.spk` is intentionally treated
as invalid for DSM installation because `lab` is not a numeric version segment.

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
sh scripts/check-spk-archive.sh --spk build/spk/lxc-on-dsm-0.1.0-0010.spk
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
build/spk/lxc-on-dsm-0.1.0-0009.spk
```

The next helper package-tool gate produces:

```text
build/spk/lxc-on-dsm-0.1.0-0010.spk
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

## First install-attempt evidence

The first Virtual DSM CLI install attempt for the earlier artifact failed
before `/var/packages/lxc-on-dsm` was created:

```text
error code 261: invalid package info content
```

That failure is a metadata/package-layout gate, not runtime damage. The follow-up
fixes keep the install test focused on a DSM-7-valid archive first; package
`start` remains a later privilege/runtime gate.

The second Virtual DSM gate installed `0.1.0-0001` successfully, but
`synopkg start` failed with script exit `126`. Manual root execution of
`/var/packages/lxc-on-dsm/scripts/start-stop-status start` worked and started
the macvlan lifecycle, while execution as `lxc_on_dsm` failed with permission
denied on `target/scripts/doctor-macvlan-profile.sh`. Evidence showed
`/var/packages/lxc-on-dsm/target/scripts` installed as `d---------` and the
manually copied profile as `---------- root root`.

The `0.1.0-0002` package gate then tried explicit `conf/privilege` `tool`
permissions for `target/scripts`, but DSM rejected installation with error
`313` (`failed to revise file attributes`). The `0.1.0-0003` gate therefore
keeps `conf/privilege` minimal and moves target permission repair into
`postinst`, while still shipping `target/config/lab-macvlan.env.example`.
The install plan also makes the copied lab profile package-owned and readable
before testing package `status` or `start`.

The `0.1.0-0003` package then installed successfully and the package user could
execute the wrapper, but the doctor could not read the existing lab container
because `/volume1/@lxc/lab/containers` and the container directory were
`0700 root:root`, with `config` at `0600 root:root`. The `0.1.0-0004` gate adds
`prepare-package-access.sh`, a dry-run-first script that sets only the minimal
container-state access needed by the package user: traverse on the state and
container directories plus read access on the LXC config.

After `0.1.0-0004`, package-user `status` passed, but package-user `start`
failed before LXC startup because the lifecycle script tried to create the
relative default `artifacts/` directory from an unwritable working directory.
The `0.1.0-0005` gate makes the package wrapper pass
`/var/packages/lxc-on-dsm/var/artifacts` explicitly for start/stop logs and
has `postinst` create that package-owned directory.

After `0.1.0-0005`, package-user `start` reached `lxc-start`, which aborted
without detailed diagnostics in the lifecycle log. It also exposed stale
root-owned lifecycle evidence handling. The `0.1.0-0006` gate adds per-run
evidence filenames, captures an LXC debug logfile with `--logfile` and updates
package access preparation to use a package group model that permits writing
`lifecycle-state.env` without making the container directory world-writable.

The `0.1.0-0006` debug log showed the expected privileged-runtime gate:
legacy cgroup hierarchies were not writable and LXC failed with
`Permission denied - Failed to pin rootfs` while running as `lxc_on_dsm`.
The `0.1.0-0007` gate tried root `ctrl-script` actions, but DSM rejected the
privilege file with error `319` (`invalid package privilege content`). The
`0.1.0-0008` gate removes `ctrl-script` entirely and uses a minimal root
`defaults.run-as` privilege file for the experimental package lifecycle.

DSM rejected `0.1.0-0008` as well with error `319`, proving that this unsigned
third-party lab package cannot simply request root execution in
`conf/privilege`. The `0.1.0-0009` gate returns to a valid `run-as: package`
privilege file and makes Package Center `start`/`stop` fail fast with a clear
root-lifecycle diagnostic. The known-good privileged lifecycle remains available
only as an explicit root command, pending a Resource Worker design.

`0.1.0-0009` installed successfully in Virtual DSM. Package Center `start`
failed as expected with script exit `1`, while the explicit root package
wrapper path succeeded:

```text
sh /var/packages/lxc-on-dsm/scripts/start-stop-status start
container_ip=10.26.88.214
dhcp_status=OK
shim_created=1
route_added=1

sh /var/packages/lxc-on-dsm/scripts/start-stop-status stop
container_stopped=YES
shim_absent=YES
```

This is the current validated boundary: installable management SPK plus manual
root lifecycle. Automatic Package Center lifecycle requires the next design
gate.

## Phase 7 handoff

Do not continue by trying additional broad `conf/privilege` variants. The
validated package is `0.1.0-0009`, and it remains the stable base for the helper
package-tool investigation. The next package artifact is `0.1.0-0010`.

The next gate is read-only:

```sh
sh scripts/plan-resource-worker.sh
```

That plan investigates whether DSM Resource Workers can provide a documented
privileged boundary for the LXC lifecycle. If no suitable official worker exists,
the alternative is a separate narrow lab-only root helper design, not a generic
root package.

`0.1.0-0010` installed successfully in Virtual DSM as the package-tool handoff
gate. It ships `target/scripts/lxc-on-dsm-root-helper.sh` as a normal executable
package file without setuid/setgid, keeps Package Center `start` blocked for the
package user, and validates installed-helper manual root start, status and
stop/cleanup for the macvlan lifecycle.

## Runtime-bundled package candidate

After the DSM-native CI runtime build passed, the package payload gained an
optional `--runtime-bundle` assembly path. This copies the reviewed runtime
bundle into the package payload as:

```text
target/runtime/lxc-runtime-bundle.tar.gz
```

The bundle remains an opaque artifact inside the SPK. Package installation does
not restore it automatically, Package Center `start` remains blocked for the
package user and no container is created or started.

The package also ships explicit helper scripts:

```text
target/scripts/install-packaged-runtime.sh
target/scripts/restore-lxc-runtime-bundle.sh
target/scripts/check-lxc-runtime-deps.sh
target/scripts/create-packaged-container.sh
```

`install-packaged-runtime.sh` is dry-run by default and requires `--install`
before it writes `/volumeN/@lxc/lab/opt`.

`create-packaged-container.sh` is also dry-run by default and requires
`--create` before it writes a stopped container under
`/volumeN/@lxc/lab/containers`. It does not start the container and does not
change networking.

The package also ships a first DSM Desktop UI entry under `target/ui`. This is
documented in `docs/phase12-gui.md`.

The current package-only gate is:

```sh
sh scripts/assemble-spk-payload.sh --runtime-bundle build/gh-run-32390336678/ci-dsm-native-runtime-build/lxc-runtime-bundle-20260820T161125Z.tar.gz
sh scripts/check-spk-payload.sh
sh scripts/build-spk.sh
sh scripts/check-spk-archive.sh --spk build/spk/lxc-on-dsm-0.1.0-0010.spk
```

The CI equivalent is:

```sh
sh scripts/ci-package-runtime-spk.sh \
  --runtime-artifact-dir artifacts/ci-dsm-native-runtime-build \
  --output artifacts/ci-runtime-spk
```

The uploaded GitHub Actions artifact is named `ci-runtime-spk`. It contains the
checked `.spk`, packaging logs and a short report, but it remains a lab
candidate only. Package installation and runtime restoration are separate,
explicit operations for a non-production DSM lab.

When the CI runtime build has fetched the pinned Alpine minirootfs, the package
gate embeds it as:

```text
target/images/alpine-minirootfs.tar.gz
```

The image is a seed artifact only. Package installation does not extract it
automatically.

For local Windows/Git-Bash packaging only, the CI wrapper can skip extracting
the runtime bundle and rely on archive-listing checks instead:

```sh
sh scripts/ci-package-runtime-spk.sh \
  --runtime-artifact-dir build/gh-run-32390336678/ci-dsm-native-runtime-build \
  --output build/ci-runtime-spk-local \
  --skip-extracting-runtime-checks
```

The GitHub Actions path must run without that skip flag.

That gate passed locally. It does not install the SPK, does not restore the
runtime and does not touch any DSM host.
