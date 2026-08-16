#!/bin/sh
# Plan a CI-based Synology toolchain build without using DSM as the build host.
# This is plan-only and performs no downloads or builds.
set -eu

generated_utc=$(date -u +%Y%m%dT%H%M%SZ)

cat <<EOF
# CI Synology toolchain build plan

generated_utc=${generated_utc}

## Scope

- plan only
- does not download Synology toolchains
- does not build LXC
- does not install Entware
- does not touch the physical NAS
- does not create runtime files
- does not start containers

## Constraint

The physical DS224+ must remain runtime-only:

- no Entware
- no compiler packages
- no Meson/Ninja/pkg-config
- no source trees
- no on-device LXC build

## Build location

Use GitHub Actions or another disposable Linux CI runner as the build
environment. That runner may install build dependencies and unpack Synology's
DSM 7.3 x86_64 toolchain/build environment.

## Required output

The CI build must output a runtime bundle only:

\`\`\`text
artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz
\`\`\`

The bundle must pass:

\`\`\`sh
sh scripts/check-lxc-runtime-bundle.sh artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz
sh scripts/check-runtime-package-boundary.sh artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz
\`\`\`

The physical DS224+ must still pass:

\`\`\`sh
sh scripts/restore-lxc-runtime-bundle.sh --bundle artifacts/lxc-runtime-bundle-YYYYMMDDTHHMMSSZ.tar.gz --target /volume1/@lxc/lab/opt
sh scripts/check-lxc-runtime-deps.sh --prefix /volume1/@lxc/lab/opt
\`\`\`

## Next implementation step

Add a manual GitHub Actions workflow skeleton that:

1. records selected DSM version and platform;
2. downloads or prepares the Synology toolchain/build environment;
3. prints toolchain metadata;
4. uploads a reconnaissance artifact;
5. does not build LXC until the platform is confirmed.

Result: CI TOOLCHAIN BUILD PLAN GENERATED. No system state was changed.
EOF
