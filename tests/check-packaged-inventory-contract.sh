#!/bin/sh
set -eu

inventory=scripts/list-packaged-containers.sh

sh -n "$inventory"

grep -q 'PACKAGED CONTAINER INVENTORY COMPLETE' "$inventory"
grep -q 'No container was started' "$inventory"
grep -q '/volume\[0-9\]\*/@lxc/lab/containers' "$inventory"
grep -q 'lxc-info' "$inventory"
grep -q 'LD_LIBRARY_PATH=' "$inventory"
grep -q 'LXC_CONFIG_PATH=' "$inventory"

if sh "$inventory" --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly' >&2
    exit 1
fi

if sh "$inventory" --prefix /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe prefix was accepted unexpectedly' >&2
    exit 1
fi

printf '%s\n' 'Packaged inventory contract checks passed.'
