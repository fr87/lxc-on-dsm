#!/bin/sh
# Generate a read-only Phase 7 plan for DSM Resource Worker / privileged helper research.
# Does not change package metadata, start containers or call synopkghelper update.
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
plan_file="${output_dir}/resource-worker-plan-${stamp}.md"

{
    printf '%s\n' '# DSM Resource Worker / privileged lifecycle plan'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'package=%s\n' "$package_name"
    printf 'profile=%s\n' "$profile_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- plan only'
    printf '%s\n' '- Virtual DSM lab system only'
    printf '%s\n' '- read-only reconnaissance commands only'
    printf '%s\n' '- does not modify `conf/resource` or `conf/privilege`'
    printf '%s\n' '- does not install, repair, start or stop the package'
    printf '%s\n' '- does not start containers'
    printf '%s\n' '- does not create interfaces, routes, bridges or firewall rules'
    printf '%s\n' '- does not call `synopkghelper update`'
    printf '\n'
    printf '%s\n' '## Current validated boundary'
    printf '\n'
    printf '%s\n' '- `0.1.0-0009` is installable in Virtual DSM with `run-as: package`.'
    printf '%s\n' '- Package Center `start` is expected to block at the root lifecycle gate.'
    printf '%s\n' '- Manual root execution of the installed package wrapper starts and stops the macvlan lifecycle.'
    printf '%s\n' '- Unsigned attempts to request root lifecycle execution through package privilege metadata were rejected by DSM with error `319`.'
    printf '\n'
    printf '%s\n' '## Official DSM design direction to review'
    printf '\n'
    printf '%s\n' '- DSM 7 packages are expected to run with lower privileges and declare `conf/privilege`.'
    printf '%s\n' '- Privileged needs should be mapped through documented resource acquisition where possible.'
    printf '%s\n' '- A Synology development token is not a portable default for this public lab project.'
    printf '\n'
    printf '%s\n' 'Reference pages to review:'
    printf '\n'
    printf '%s\n' '- https://help.synology.com/developer-guide/breaking_changes.html'
    printf '%s\n' '- https://help.synology.com/developer-guide/privilege/preface.html'
    printf '%s\n' '- https://help.synology.com/developer-guide/privilege/privilege_config.html'
    printf '%s\n' '- https://help.synology.com/developer-guide/resource_acquisition/resources.html'
    printf '%s\n' '- https://help.synology.com/developer-guide/getting_started/system_requirement.html'
    printf '\n'
    printf '%s\n' '## Read-only Virtual DSM reconnaissance'
    printf '\n'
    printf '%s\n' 'Run manually as root in the Virtual DSM lab and paste the output back into the project discussion:'
    printf '\n'
    printf '```sh\n'
    printf 'synopkg status %s\n' "$package_name"
    printf 'ls -la /var/packages/%s\n' "$package_name"
    printf 'ls -la /var/packages/%s/conf\n' "$package_name"
    printf 'if [ -r /var/packages/%s/conf/privilege ]; then sed -n '"'"'1,200p'"'"' /var/packages/%s/conf/privilege; fi\n' "$package_name" "$package_name"
    printf 'if [ -r /var/packages/%s/conf/resource ]; then sed -n '"'"'1,200p'"'"' /var/packages/%s/conf/resource; fi\n' "$package_name" "$package_name"
    printf 'ls -la /usr/syno/sbin/synopkghelper\n'
    printf '/usr/syno/sbin/synopkghelper --help 2>&1 | sed -n '"'"'1,120p'"'"'\n'
    printf 'find /usr/syno -path '"'"'*resource*'"'"' -o -path '"'"'*synopkg*'"'"' 2>/dev/null | sed -n '"'"'1,160p'"'"'\n'
    printf '```\n'
    printf '\n'
    printf '%s\n' 'These commands inspect the installed package and DSM helper surface. They should not start a container or mutate package state.'
    printf '\n'
    printf '%s\n' '## Commands not approved by this plan'
    printf '\n'
    printf '%s\n' 'Do not run these until a concrete `conf/resource` design has been reviewed:'
    printf '\n'
    printf '```sh\n'
    printf '/usr/syno/sbin/synopkghelper update %s RESOURCE_ID\n' "$package_name"
    printf 'synopkg start %s\n' "$package_name"
    printf 'synopkg repair %s\n' "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' '## Decision gate'
    printf '\n'
    printf '%s\n' 'After collecting the reconnaissance output, choose exactly one next path:'
    printf '\n'
    printf '%s\n' '1. Add a real `conf/resource.template` only if an official Resource Worker matches the LXC lifecycle need.'
    printf '%s\n' '2. Design a narrow lab-only root helper if no official worker fits.'
    printf '%s\n' '3. Keep `0.1.0-0009` as an installable management SPK with manual root lifecycle only.'
    printf '\n'
    printf '%s\n' '## Minimum helper contract if path 2 is chosen later'
    printf '\n'
    printf '%s\n' '- no generic root shell'
    printf '%s\n' '- no arbitrary command execution'
    printf '%s\n' '- explicit verbs only: `start`, `stop`, and possibly `doctor`'
    printf '%s\n' '- profile path restricted to the package configuration area'
    printf '%s\n' '- state path restricted to the reviewed `/volumeN/@lxc/lab` layout'
    printf '%s\n' '- cleanup-first failure handling'
    printf '%s\n' '- auditable logs under `/var/packages/lxc-on-dsm/var/artifacts`'
    printf '%s\n' '- autostart stays disabled until recovery has been proven'
    printf '\n'
    printf '%s\n' 'Result: RESOURCE WORKER PLAN GENERATED. No DSM package was changed.'
} >"$plan_file"

cat "$plan_file"
