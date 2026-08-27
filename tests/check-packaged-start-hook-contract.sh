#!/bin/sh
set -eu

installer=scripts/install-packaged-start-hook.sh

sh -n "$installer"

grep -q 'PACKAGED START HOOK INSTALL DRY RUN COMPLETE' "$installer"
grep -q 'PACKAGED START HOOK INSTALLED' "$installer"
grep -q 'No container was started' "$installer"
grep -q 'Packaged start hook install requires uid=0' "$installer"
grep -q '/etc/lxc-on-dsm/start.d' "$installer"
grep -q 'lxc-on-dsm container start hook dispatcher' "$installer"

if sh "$installer" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly by hook installer' >&2
    exit 1
fi

if sh "$installer" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly by hook installer' >&2
    exit 1
fi

printf '%s\n' 'Packaged start hook contract checks passed.'
