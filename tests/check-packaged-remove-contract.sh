#!/bin/sh
set -eu

remover=scripts/remove-packaged-container.sh

sh -n "$remover"

grep -q 'PACKAGED CONTAINER REMOVE DRY RUN COMPLETE' "$remover"
grep -q 'PACKAGED CONTAINER REMOVED' "$remover"
grep -q 'PACKAGED CONTAINER BACKED UP' "$remover"
grep -q 'No files were removed' "$remover"
grep -q 'No container was started' "$remover"
grep -q 'Refusing to remove running container' "$remover"
grep -q 'requires uid=0' "$remover"
grep -q '/volume\[0-9\]\*/@lxc/lab/containers' "$remover"
grep -q '/var/packages/"${package_name}"/var/artifacts' "$remover"

if sh "$remover" --name '../bad' >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly' >&2
    exit 1
fi

if sh "$remover" --name ok --state-dir /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe state dir was accepted unexpectedly' >&2
    exit 1
fi

if sh "$remover" --name ok --output /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe output dir was accepted unexpectedly' >&2
    exit 1
fi

printf '%s\n' 'Packaged remove contract checks passed.'
