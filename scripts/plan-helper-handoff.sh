#!/bin/sh
# Generate a reviewable handoff plan from experimental helper to package lifecycle.
# Does not copy files, modify package scripts, install a helper, or start containers.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--helper FILE] [--profile FILE] [--output DIRECTORY]"
}

package_name=lxc-on-dsm
helper_file=scripts/experimental/lxc-on-dsm-root-helper.sh
profile_file=/var/packages/lxc-on-dsm/etc/lab-macvlan.env
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --helper) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; helper_file=$2; shift 2 ;;
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
plan_file="${output_dir}/helper-handoff-plan-${stamp}.md"

{
    printf '%s\n' '# Helper handoff plan'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'package=%s\n' "$package_name"
    printf 'helper=%s\n' "$helper_file"
    printf 'profile=%s\n' "$profile_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- plan only'
    printf '%s\n' '- does not copy helper files'
    printf '%s\n' '- does not install a helper'
    printf '%s\n' '- does not modify package scripts'
    printf '%s\n' '- does not modify `conf/resource` or `conf/privilege`'
    printf '%s\n' '- does not change setuid bits, sudoers or file ownership'
    printf '%s\n' '- does not start or stop containers'
    printf '%s\n' '- does not change networking'
    printf '\n'
    printf '%s\n' '## Validated evidence required before handoff'
    printf '\n'
    printf '%s\n' '- helper dry-run for `start`, `stop` and `status` prints fixed target scripts'
    printf '%s\n' '- helper real root `status` reports stopped/clean state'
    printf '%s\n' '- helper real root `start` reports DHCP OK, shim created and route added'
    printf '%s\n' '- helper real root `status` reports RUNNING, shim present and route present'
    printf '%s\n' '- helper real root `stop` reports container stopped and shim absent'
    printf '%s\n' '- helper final real root `status` reports stopped/clean state'
    printf '\n'
    printf '%s\n' '## Handoff design choice'
    printf '\n'
    printf '%s\n' 'Choose one of these before any package change:'
    printf '\n'
    printf '%s\n' '1. Keep helper experimental and manual-only.'
    printf '%s\n' '2. Ship helper as a non-privileged package tool but require root to execute it manually.'
    printf '%s\n' '3. Add an administrator-installed root-owned helper outside Package Center control.'
    printf '%s\n' '4. Add Package Center delegation only if DSM provides a reviewed root invocation mechanism.'
    printf '\n'
    printf '%s\n' 'Current recommendation for the lab: option 2 first. It reduces path drift but still requires an explicit root shell.'
    printf '\n'
    printf '%s\n' '## Option 2 package changes, if accepted later'
    printf '\n'
    printf '%s\n' '- copy the helper into `target/scripts/lxc-on-dsm-root-helper.sh`'
    printf '%s\n' '- keep `conf/privilege` as `run-as: package`'
    printf '%s\n' '- keep Package Center `start`/`stop` blocked for non-root execution'
    printf '%s\n' '- update the blocker message to point at the installed helper path'
    printf '%s\n' '- add archive checks proving the helper is present but not setuid'
    printf '%s\n' '- validate manual root helper start/stop after installing the next SPK'
    printf '\n'
    printf '%s\n' '## Commands to run before accepting option 2'
    printf '\n'
    printf '```sh\n'
    printf 'sh tests/check-root-helper-contract.sh\n'
    printf 'sh scripts/experimental/lxc-on-dsm-root-helper.sh --dry-run start --profile %s\n' "$profile_file"
    printf 'sh scripts/experimental/lxc-on-dsm-root-helper.sh --dry-run stop --profile %s\n' "$profile_file"
    printf 'sh scripts/experimental/lxc-on-dsm-root-helper.sh --dry-run status --profile %s\n' "$profile_file"
    printf '```\n'
    printf '\n'
    printf '%s\n' '## Commands not approved by this plan'
    printf '\n'
    printf '```sh\n'
    printf 'chmod u+s ANYTHING\n'
    printf 'synopkg start %s\n' "$package_name"
    printf 'synopkg repair %s\n' "$package_name"
    printf 'cp %s /var/packages/%s/target/scripts/\n' "$helper_file" "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' 'Result: HELPER HANDOFF PLAN GENERATED. No DSM package was changed.'
} >"$plan_file"

cat "$plan_file"
