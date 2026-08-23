#!/bin/sh
set -eu

probe=scripts/run-packaged-macvlan-dhcp-test.sh

sh -n "$probe"

grep -q 'PACKAGED MACVLAN DHCP TEST DRY RUN COMPLETE' "$probe"
grep -q 'PACKAGED MACVLAN DHCP TEST COMPLETE' "$probe"
grep -q 'Packaged macvlan DHCP test requires uid=0' "$probe"
grep -q 'lxc.net.0.type = macvlan' "$probe"
grep -q 'lxc.start.auto = 0' "$probe"
grep -q 'Parent interface does not exist, refusing to start container' "$probe"
grep -q 'Container is already running, refusing to take over' "$probe"
grep -q '/volume\[0-9\]\*/@lxc/lab/containers' "$probe"
grep -q '/volume\[0-9\]\*/@lxc/lab/opt' "$probe"

if sh "$probe" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly' >&2
    exit 1
fi

if sh "$probe" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly' >&2
    exit 1
fi

if sh "$probe" --name ok --prefix /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe prefix was accepted unexpectedly' >&2
    exit 1
fi

printf '%s\n' 'Packaged macvlan DHCP contract checks passed.'
