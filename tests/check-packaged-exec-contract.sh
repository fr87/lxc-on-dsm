#!/bin/sh
set -eu

executor=scripts/exec-packaged-container.sh

sh -n "$executor"

grep -q 'PACKAGED CONTAINER EXEC DRY RUN COMPLETE' "$executor"
grep -q 'PACKAGED CONTAINER EXEC COMPLETE' "$executor"
grep -q 'Packaged container exec requires uid=0' "$executor"
grep -q 'lxc-attach' "$executor"
grep -q 'LD_LIBRARY_PATH=' "$executor"
grep -q 'LXC_CONFIG_PATH=' "$executor"

if sh "$executor" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly by exec wrapper' >&2
    exit 1
fi

if sh "$executor" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly by exec wrapper' >&2
    exit 1
fi

printf '%s\n' 'Packaged exec contract checks passed.'
