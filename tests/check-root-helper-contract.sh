#!/bin/sh
set -eu

helper=scripts/experimental/lxc-on-dsm-root-helper.sh
profile=/var/packages/lxc-on-dsm/etc/lab-macvlan.env

sh -n "$helper"

output=$(sh "$helper" --dry-run start --profile "$profile")
printf '%s\n' "$output" | grep -q 'verb=start'
printf '%s\n' "$output" | grep -q 'target_script=/var/packages/lxc-on-dsm/target/scripts/start-macvlan-profile.sh'
printf '%s\n' "$output" | grep -q 'Result: ROOT HELPER DRY RUN COMPLETE'

output=$(sh "$helper" --dry-run stop --profile "$profile")
printf '%s\n' "$output" | grep -q 'verb=stop'
printf '%s\n' "$output" | grep -q 'target_script=/var/packages/lxc-on-dsm/target/scripts/stop-macvlan-profile.sh'

output=$(sh "$helper" --dry-run status --profile "$profile")
printf '%s\n' "$output" | grep -q 'verb=status'
printf '%s\n' "$output" | grep -q 'target_script=/var/packages/lxc-on-dsm/target/scripts/doctor-macvlan-profile.sh'

if sh "$helper" --dry-run restart --profile "$profile" >/dev/null 2>&1; then
    printf '%s\n' 'restart verb was accepted unexpectedly' >&2
    exit 1
fi

if sh "$helper" --dry-run start --profile config/lab-macvlan.env >/dev/null 2>&1; then
    printf '%s\n' 'relative profile path was accepted unexpectedly' >&2
    exit 1
fi

if sh "$helper" --dry-run start --profile /var/packages/lxc-on-dsm/etc/../evil.env >/dev/null 2>&1; then
    printf '%s\n' 'unsafe profile path was accepted unexpectedly' >&2
    exit 1
fi

if sh "$helper" --dry-run start --profile "$profile" --output /tmp/lxc-on-dsm >/dev/null 2>&1; then
    printf '%s\n' 'unsafe output path was accepted unexpectedly' >&2
    exit 1
fi

printf '%s\n' 'Root helper contract checks passed.'
