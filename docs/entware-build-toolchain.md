# Entware build toolchain notes

Phase 2 needs a DSM-local toolchain only inside Virtual DSM. Installing Entware packages changes the Virtual DSM environment and should not be done on the physical DS224+ until the build process is understood.

The current Virtual DSM check shows:

- no `/opt`-style prefix
- no `opkg`
- no `pkg-config` or `pkgconf`
- no `meson`
- no `ninja`
- no compiler in `PATH`

## Entware baseline

The Entware Synology guide uses a persistent folder outside the DSM root filesystem, commonly:

```text
/volume1/@Entware/opt
```

Then `/opt` is bind-mounted to that folder. This matters because DSM updates can recreate or erase root filesystem paths.

Generate a lab-specific command plan:

```sh
sh scripts/plan-entware-bootstrap.sh --volume /volume1 --output artifacts/entware-bootstrap-plan.md
```

The generated plan is intentionally not an installer. Review the commands, then run them manually inside Virtual DSM as `root`.

## Native build packages

Entware's native GCC notes recommend installing GCC plus common build helpers:

```sh
opkg update
opkg install gcc
opkg install binutils busybox gawk ldd make sed tar
opkg install coreutils-install diffutils ldconfig patch pkgconf --force-overwrite
opkg install bash git python3-pip python3-setuptools
python3 -m pip install -U wheel meson
```

The current x64 Entware feed no longer exposes `pkg-config` as an installable package. If `check-phase2-prereqs.sh` still reports `pkg-config` or `pkgconf` missing after the package step, bootstrap `pkgconf` from pinned source:

```sh
sh scripts/fetch-sources.sh --output /volume1/Dev/lxc-on-dsm/build/sources
sh scripts/build-pkgconf.sh --prefix /opt --install
```

Entware's Meson/Ninja notes build Ninja from source when a package is not available:

```sh
export PATH="/opt/bin:/opt/sbin:$PATH"
mkdir -p /opt/tmp
cd /opt/tmp
rm -rf ninja-release ninja.tar.gz
curl -fL https://github.com/ninja-build/ninja/archive/refs/heads/release.tar.gz -o ninja.tar.gz
tar -xzf ninja.tar.gz
cd ninja-release
CONFIG_SHELL=/opt/bin/bash python3 ./configure.py --bootstrap
install -Dm0755 -t /opt/bin ./ninja
cd /opt/tmp
rm -rf ninja-release ninja.tar.gz
```

## Environment

For native Entware builds, source the GCC environment before compiling:

```sh
. /opt/bin/gcc_env.sh
```

This is important because Entware binaries use `/opt/lib` and a non-standard dynamic linker. The project scripts add `/opt/bin` and `/opt/sbin` to `PATH`, but they do not install Entware or modify DSM profile files.

## References

- Entware on Synology NAS: https://github-wiki-see.page/m/entware/entware/wiki/Install-on-Synology-NAS
- Entware native GCC notes: https://github-wiki-see.page/m/entware/entware/wiki/Using-GCC-for-native-compilation
