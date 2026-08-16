#!/bin/sh
# Generate a reviewable plan for a narrow lab-only root helper.
# Does not install a helper, change package metadata, start containers or change networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--profile FILE] [--output DIRECTORY]"
}

package_name=lxc-on-dsm
profile_file=/var/packages/lxc-on-dsm/etc/lab-macvlan.env
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
plan_file="${output_dir}/root-helper-plan-${stamp}.md"

{
    printf '%s\n' '# Narrow root helper plan'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'package=%s\n' "$package_name"
    printf 'profile=%s\n' "$profile_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- plan only'
    printf '%s\n' '- Virtual DSM lab system only'
    printf '%s\n' '- does not install a helper'
    printf '%s\n' '- does not modify `conf/resource` or `conf/privilege`'
    printf '%s\n' '- does not change setuid bits, sudoers or file ownership'
    printf '%s\n' '- does not start or stop containers'
    printf '%s\n' '- does not create interfaces, routes, bridges or firewall rules'
    printf '\n'
    printf '%s\n' '## Why this path is being planned'
    printf '\n'
    printf '%s\n' '- Package `0.1.0-0009` is installable with DSM 7 `run-as: package`.'
    printf '%s\n' '- Package Center lifecycle cannot run LXC as `lxc_on_dsm` because rootfs, cgroup and network operations are privileged.'
    printf '%s\n' '- Unsigned attempts to request root lifecycle execution through package privilege metadata were rejected by DSM.'
    printf '%s\n' '- Resource Worker reconnaissance has not shown an official worker that covers the LXC lifecycle.'
    printf '\n'
    printf '%s\n' '## Proposed helper boundary'
    printf '\n'
    printf '%s\n' 'The helper should be treated as a small policy gate, not as a shell wrapper.'
    printf '\n'
    printf '%s\n' 'Allowed input:'
    printf '\n'
    printf '%s\n' '- one verb: `start`, `stop` or `status`'
    printf '%s\n' '- one fixed package id: `lxc-on-dsm`'
    printf '%s\n' '- one reviewed profile path under `/var/packages/lxc-on-dsm/etc/`'
    printf '\n'
    printf '%s\n' 'Rejected input:'
    printf '\n'
    printf '%s\n' '- arbitrary commands'
    printf '%s\n' '- arbitrary script paths'
    printf '%s\n' '- environment-controlled executable paths'
    printf '%s\n' '- profile paths outside the package configuration directory'
    printf '%s\n' '- container names with characters outside `[A-Za-z0-9_.-]`'
    printf '%s\n' '- state directories outside `/volume[0-9]*/@lxc/lab/containers`'
    printf '\n'
    printf '%s\n' '## Required helper preflight'
    printf '\n'
    printf '%s\n' 'Before a helper performs any privileged action, it must verify:'
    printf '\n'
    printf '%s\n' '- effective uid is root'
    printf '%s\n' '- package target, etc and var symlinks resolve as expected'
    printf '%s\n' '- profile is readable and owned by the package user or root'
    printf '%s\n' '- LXC prefix exists and contains the expected `lxc-start`, `lxc-stop` and `lxc-info` binaries'
    printf '%s\n' '- container config exists and is configured for macvlan on the reviewed parent interface'
    printf '%s\n' '- container autostart is disabled'
    printf '%s\n' '- shim interface is absent before start'
    printf '%s\n' '- lifecycle state is absent before start, or is explicitly reconciled by `stop`'
    printf '\n'
    printf '%s\n' '## Lifecycle behavior'
    printf '\n'
    printf '%s\n' '`start` should:'
    printf '\n'
    printf '%s\n' '1. run the same doctor gates used by the current package scripts'
    printf '%s\n' '2. start only the configured container'
    printf '%s\n' '3. capture DHCP/container IP evidence'
    printf '%s\n' '4. create only the configured host macvlan shim if needed'
    printf '%s\n' '5. add only the lifecycle-owned host route to the detected container IP'
    printf '%s\n' '6. write auditable state and logs under `/var/packages/lxc-on-dsm/var/artifacts`'
    printf '\n'
    printf '%s\n' '`stop` should:'
    printf '\n'
    printf '%s\n' '1. stop only the configured container'
    printf '%s\n' '2. remove only lifecycle-owned route and shim state'
    printf '%s\n' '3. preserve container rootfs and config'
    printf '%s\n' '4. succeed idempotently when the container is already stopped'
    printf '\n'
    printf '%s\n' '`status` should remain read-only and should not require root if the package user can read the necessary state.'
    printf '\n'
    printf '%s\n' '## Prototype gate order'
    printf '\n'
    printf '%s\n' '1. Write a helper contract document and threat model.'
    printf '%s\n' '2. Add a non-installed helper prototype under `target/` or `scripts/experimental/`.'
    printf '%s\n' '3. Add shell-safety tests that reject arbitrary paths and verbs.'
    printf '%s\n' '4. Add a manual install plan for Virtual DSM only.'
    printf '%s\n' '5. Validate start/stop manually from root.'
    printf '%s\n' '6. Only then decide whether Package Center `start` may delegate to the helper.'
    printf '\n'
    printf '%s\n' '## Open decision'
    printf '\n'
    printf '%s\n' 'The safest current operational mode remains manual root execution of the installed wrapper. The helper path should be accepted only if the reduced operational friction is worth the extra privileged component.'
    printf '\n'
    printf '%s\n' 'Result: ROOT HELPER PLAN GENERATED. No DSM package was changed.'
} >"$plan_file"

cat "$plan_file"
