# Phase 12: minimal DSM GUI entrypoint

The first GUI scope is deliberately small. It adds a DSM Desktop entry that
opens a local package page from the installed package payload. The page is a
safe control panel and command handoff, not a privileged browser backend.

## DSM integration shape

Synology's package guide describes `dsmuidir` as the package payload directory
that DSM links into the Desktop third-party application area. Synology's Desktop
Application guide also requires a matching `dsmappname` entry in `INFO`, and
the Application Config guide documents URL applications that can point to a
local `3rdparty/<package>/index.html` page.

This package now declares:

```text
dsmuidir="ui"
dsmappname="com.fr87.LxcOnDsmLab"
```

and ships:

```text
target/ui/config
target/ui/index.html
target/ui/style.css
target/ui/app.js
target/ui/status.json
target/ui/images/icon_{16,24,32,48,64,72,256}.png
```

The UI config registers `com.fr87.LxcOnDsmLab` as a local URL app:

```text
3rdparty/lxc-on-dsm/index.html
```

## Current GUI behavior

The page shows the reviewed admin command sequence:

1. dry-run packaged runtime restore;
2. explicit runtime restore;
3. dry-run container creation;
4. explicit stopped-container creation;
5. package-owned networkless smoke test;
6. read-only lifecycle status;
7. explicit root-helper start/stop.

It does not execute commands in the browser, does not run as root, does not
restore runtime files, does not create containers and does not start containers.

The page reads a static `status.json` manifest generated at package assembly
time. This is intentionally build/package state only, not live host state.

## Validation gates

The package checks now verify:

- `dsmuidir` and `dsmappname` metadata exist in `INFO`;
- `target/ui/config`, HTML/CSS/JS, status manifest and icon files are present in
  `package.tgz`;
- the UI config points to the local package URL;
- the UI page explains the root lifecycle gate.

Local gates passed for management-only SPK with UI and runtime-bundled SPK with
UI and a test image seed. Both gates are package-only.

Virtual DSM validation on 2026-08-23 installed the CI-built runtime-bundled SPK
from GitHub Actions run `32652387021`. The installed package exposed:

```text
target/ui/config
target/ui/index.html
target/ui/style.css
target/ui/app.js
target/ui/status.json
target/ui/images/icon_{16,24,32,48,64,72,256}.png
target/runtime/lxc-runtime-bundle.tar.gz
target/images/alpine-minirootfs.tar.gz
```

The installed `status.json` reported:

```json
{
  "package": "lxc-on-dsm",
  "version": "0.1.0-0010",
  "mode": "experimental-lab",
  "runtime_bundle_packaged": true,
  "alpine_image_packaged": true
}
```

The productive physical DS224+ was not contacted for this validation.

## References

- Synology Developer Guide: Launch an App
  <https://help.synology.com/developer-guide/synology_package/package_tgz/launch_app.html>
- Synology Developer Guide: Desktop Application
  <https://help.synology.com/developer-guide/integrate_dsm/desktopapp.html>
- Synology Developer Guide: Application Config
  <https://help.synology.com/developer-guide/integrate_dsm/config.html>
