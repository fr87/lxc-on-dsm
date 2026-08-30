#!/bin/sh
set -eu

installer=scripts/install-packaged-hook-snippet.sh

sh -n "$installer"

grep -q 'PACKAGED HOOK SNIPPET INSTALL DRY RUN COMPLETE' "$installer"
grep -q 'PACKAGED HOOK SNIPPET INSTALLED' "$installer"
grep -q 'No container was started' "$installer"
grep -q 'Packaged hook snippet install requires uid=0' "$installer"
grep -Fq '/var/packages/"${package_name}"/etc/hooks/*.sh' "$installer"
grep -Fq '/volume[0-9]*/@appconf/"${package_name}"/hooks/*.sh' "$installer"

if sh "$installer" --name '../bad' --snippet ok --source /var/packages/lxc-on-dsm/etc/hooks/ok.sh >/dev/null 2>&1; then
    printf '%s\n' 'unsafe container name was accepted unexpectedly by hook snippet installer' >&2
    exit 1
fi

if sh "$installer" --name ok --snippet '../bad' --source /var/packages/lxc-on-dsm/etc/hooks/ok.sh >/dev/null 2>&1; then
    printf '%s\n' 'unsafe snippet name was accepted unexpectedly by hook snippet installer' >&2
    exit 1
fi

if sh "$installer" --name ok --snippet ok --source /tmp/ok.sh >/dev/null 2>&1; then
    printf '%s\n' 'unsafe source path was accepted unexpectedly by hook snippet installer' >&2
    exit 1
fi

printf '%s\n' 'Packaged hook snippet contract checks passed.'
