#!/bin/sh
set -eu

starter=scripts/start-packaged-container.sh
stopper=scripts/stop-packaged-container.sh

sh -n "$starter"
sh -n "$stopper"

grep -q 'PACKAGED CONTAINER START DRY RUN COMPLETE' "$starter"
grep -q 'PACKAGED CONTAINER STARTED' "$starter"
grep -q 'Packaged container start requires uid=0' "$starter"
grep -q 'lxc.start.auto = 0' "$starter"
grep -q 'empty|macvlan' "$starter"
grep -q 'Refusing persistent start for lxc.net.0.type = none' "$starter"
grep -q 'LD_LIBRARY_PATH=' "$starter"
grep -q 'LXC_CONFIG_PATH=' "$starter"

grep -q 'PACKAGED CONTAINER STOPPED' "$stopper"
grep -q 'Packaged container stop requires uid=0' "$stopper"
grep -q 'LD_LIBRARY_PATH=' "$stopper"
grep -q 'LXC_CONFIG_PATH=' "$stopper"

if sh "$starter" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly by starter' >&2
    exit 1
fi

if sh "$stopper" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly by stopper' >&2
    exit 1
fi

if sh "$starter" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly by starter' >&2
    exit 1
fi

if sh "$stopper" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly by stopper' >&2
    exit 1
fi

printf '%s\n' 'Packaged start/stop contract checks passed.'
