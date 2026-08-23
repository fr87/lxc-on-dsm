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
5. read-only lifecycle status;
6. explicit root-helper start/stop.

It does not execute commands in the browser, does not run as root, does not
restore runtime files, does not create containers and does not start containers.

## Validation gates

The package checks now verify:

- `dsmuidir` and `dsmappname` metadata exist in `INFO`;
- `target/ui/config`, `target/ui/index.html` and `target/ui/style.css` are
  present in `package.tgz`;
- the UI config points to the local package URL;
- the UI page explains the root lifecycle gate.

Local gates passed for:

- management-only SPK with UI;
- runtime-bundled SPK with UI and a test image seed.

Both gates are package-only. No DSM host was contacted.

## Known open item

The first GUI version intentionally ships no custom icon. Synology's Application
Config documentation describes an `icon` property for URL applications. If
Virtual DSM shows the app without an acceptable icon or rejects the shortcut,
add package icon assets as the next small GUI follow-up.

## References

- Synology Developer Guide: Launch an App
  <https://help.synology.com/developer-guide/synology_package/package_tgz/launch_app.html>
- Synology Developer Guide: Desktop Application
  <https://help.synology.com/developer-guide/integrate_dsm/desktopapp.html>
- Synology Developer Guide: Application Config
  <https://help.synology.com/developer-guide/integrate_dsm/config.html>
