#!/bin/sh
set -eu

creator=scripts/create-packaged-container.sh

sh -n "$creator"

grep -q 'PACKAGED CONTAINER CREATE DRY RUN COMPLETE' "$creator"
grep -q 'PACKAGED CONTAINER CREATED STOPPED' "$creator"
grep -q 'No container was started' "$creator"
grep -q 'Container creation requires uid=0' "$creator"
grep -q '/volume\[0-9\]\*/@lxc/lab/containers' "$creator"
grep -q 'lxc.start.auto = 0' "$creator"

if sh "$creator" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly' >&2
    exit 1
fi

if sh "$creator" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly' >&2
    exit 1
fi

if sh "$creator" --name ok --image /tmp/rootfs.tar.gz >/dev/null 2>&1; then
    printf '%s\n' 'unsafe image path was accepted unexpectedly' >&2
    exit 1
fi

printf '%s\n' 'Packaged container contract checks passed.'
