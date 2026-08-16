#!/bin/sh
# Plan the next runtime build path without requiring Entware on the physical NAS.
# This is a plan-only script.
set -eu

generated_utc=$(date -u +%Y%m%dT%H%M%SZ)

cat <<EOF
# DSM-native LXC runtime plan

generated_utc=${generated_utc}

## Scope

- plan only
- does not install Entware
- does not build LXC
- does not restore runtime files
- does not start containers
- does not change networking

## Current blocker

The first Virtual DSM runtime bundle was built with an Entware toolchain.
Its LXC binaries request:

\`\`\`text
/opt/lib/ld-linux-x86-64.so.2
\`\`\`

That is acceptable only on a lab system where Entware owns \`/opt\`. It is not
acceptable for the physical DS224+ target because Entware should not be
installed there.

## Required hardware-ready property

A hardware-ready runtime must pass:

\`\`\`sh
sh scripts/check-lxc-runtime-deps.sh --prefix /volume1/@lxc/lab/opt
\`\`\`

without reporting an Entware \`/opt\` interpreter.

Preferred interpreter target:

\`\`\`text
/lib64/ld-linux-x86-64.so.2
\`\`\`

or another DSM-provided system loader observed on the physical NAS.

## Candidate build paths

1. DSM-native build environment

   Build LXC with a DSM/Synology-compatible toolchain so binaries link against
   the DSM system loader and compatible system libraries.

2. Relocatable private runtime

   Bundle a private loader and runtime libraries inside the LXC prefix and use
   explicit launch wrappers. This avoids Entware but increases packaging and
   audit complexity.

3. Interpreter rewrite experiment

   Patch the Entware-built binaries from \`/opt/lib/ld-linux-x86-64.so.2\` to
   DSM's loader only as a controlled experiment. This is lower confidence
   because libc/libgcc/libstdc++ compatibility may still fail.

## Recommended next gate

Do not install Entware on the physical NAS.

Next implementation step:

1. Add an interpreter/dependency report to runtime bundle creation.
2. Build or obtain a non-Entware runtime candidate.
3. Validate the candidate with \`check-lxc-runtime-bundle.sh\`.
4. Dry-run restore on the physical NAS.
5. Run \`check-lxc-runtime-deps.sh\`.
6. Only then continue with SPK/helper dry-runs.

## Current decision

The Entware-built Virtual DSM runtime bundle is kept as useful lab evidence but
is not a physical DS224+ runtime candidate.

Result: DSM-NATIVE RUNTIME PLAN GENERATED. No system state was changed.
EOF
