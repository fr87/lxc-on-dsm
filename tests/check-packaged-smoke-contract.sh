#!/bin/sh
set -eu

smoke=scripts/run-packaged-smoke-test.sh

sh -n "$smoke"

grep -q 'PACKAGED SMOKE TEST PASSED' "$smoke"
grep -q 'Packaged smoke test requires uid=0' "$smoke"
grep -q 'lxc.net.0.type = none' "$smoke"
grep -q 'lxc.start.auto = 0' "$smoke"
grep -q 'Container is already running, refusing to take over' "$smoke"
grep -q '/volume\[0-9\]\*/@lxc/lab/containers' "$smoke"
grep -q '/volume\[0-9\]\*/@lxc/lab/opt' "$smoke"

if sh "$smoke" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly' >&2
    exit 1
fi

if sh "$smoke" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly' >&2
    exit 1
fi

if sh "$smoke" --name ok --prefix /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe prefix was accepted unexpectedly' >&2
    exit 1
fi

printf '%s\n' 'Packaged smoke contract checks passed.'
