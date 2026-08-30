#!/bin/sh
set -eu

first_use=scripts/run-packaged-first-use-test.sh

sh -n "$first_use"

grep -q 'PACKAGED FIRST USE TEST DRY RUN COMPLETE' "$first_use"
grep -q 'PACKAGED FIRST USE TEST PASSED' "$first_use"
grep -q 'Packaged first-use test requires uid=0' "$first_use"
grep -q 'No runtime files were restored' "$first_use"
grep -q 'no container was created' "$first_use"
grep -q 'no networking was changed' "$first_use"
grep -q 'remove_after_test' "$first_use"
grep -q 'install-packaged-runtime.sh' "$first_use"
grep -q 'create-packaged-container.sh' "$first_use"
grep -q 'run-packaged-smoke-test.sh' "$first_use"
grep -q 'start-packaged-container.sh' "$first_use"
grep -q 'stop-packaged-container.sh' "$first_use"
grep -q 'run-packaged-macvlan-dhcp-test.sh' "$first_use"
grep -q 'remove-packaged-container.sh' "$first_use"
grep -q '/volume\[0-9\]\*/@lxc/lab/containers' "$first_use"
grep -q '/volume\[0-9\]\*/@lxc/lab/opt' "$first_use"

if sh "$first_use" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly' >&2
    exit 1
fi

if sh "$first_use" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly' >&2
    exit 1
fi

if sh "$first_use" --name ok --prefix /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe prefix was accepted unexpectedly' >&2
    exit 1
fi

if sh "$first_use" --name ok --output /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe output dir was accepted unexpectedly' >&2
    exit 1
fi

printf '%s\n' 'Packaged first-use contract checks passed.'
