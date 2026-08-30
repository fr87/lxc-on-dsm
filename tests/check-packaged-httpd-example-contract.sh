#!/bin/sh
set -eu

snippet=spk/hooks/httpd.example.sh
runner=scripts/run-packaged-httpd-example-test.sh

sh -n "$snippet"
sh -n "$runner"

grep -q 'lxc-on-dsm example service' "$snippet"
grep -q 'status=STARTED' "$snippet"
grep -q 'httpd -p "$port" -h "$docroot"' "$snippet"
grep -q 'busybox httpd -p "$port" -h "$docroot"' "$snippet"
grep -q 'nc -l -p "$port"' "$snippet"
grep -q 'lxc-on-dsm-httpd-example.env' "$snippet"

grep -q 'PACKAGED HTTP EXAMPLE TEST DRY RUN COMPLETE' "$runner"
grep -q 'PACKAGED HTTP EXAMPLE TEST PASSED' "$runner"
grep -q 'Packaged HTTP example test requires uid=0' "$runner"
grep -q 'No container was created' "$runner"
grep -q 'no service was started' "$runner"
grep -q 'no networking was changed' "$runner"
grep -q 'install-packaged-start-hook.sh' "$runner"
grep -q 'install-packaged-hook-snippet.sh' "$runner"
grep -q 'start-packaged-container.sh' "$runner"
grep -q 'stop-packaged-container.sh' "$runner"
grep -q 'remove-packaged-container.sh' "$runner"
grep -q 'http_fetch=OK' "$runner"
grep -q '/volume\[0-9\]\*/@lxc/lab/containers' "$runner"

if sh "$runner" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly' >&2
    exit 1
fi

if sh "$runner" --name ok --network-type none >/dev/null 2>&1; then
    printf '%s\n' 'unsupported network type was accepted unexpectedly' >&2
    exit 1
fi

if sh "$runner" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly' >&2
    exit 1
fi

printf '%s\n' 'Packaged HTTP example contract checks passed.'
