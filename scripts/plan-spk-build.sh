#!/bin/sh
# Generate a reviewable plan for building a DSM SPK later. Does not build an SPK.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--payload DIRECTORY] [--output DIRECTORY]"
}

package_name=lxc-on-dsm
payload_dir=build/spk-payload/lxc-on-dsm
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --payload) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; payload_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
plan_file="${output_dir}/spk-build-plan-${stamp}.md"

{
    printf '%s\n' '# DSM SPK build plan'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'package=%s\n' "$package_name"
    printf 'payload=%s\n' "$payload_dir"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- plan only'
    printf '%s\n' '- does not build an `.spk`'
    printf '%s\n' '- does not install a package'
    printf '%s\n' '- does not execute DSM package scripts'
    printf '%s\n' '- does not start containers'
    printf '%s\n' '- does not change networking'
    printf '\n'
    printf '%s\n' '## Preconditions before a real SPK builder exists'
    printf '\n'
    printf '%s\n' '1. `scripts/check-spk-skeleton.sh` passes.'
    printf '%s\n' '2. `scripts/assemble-spk-payload.sh` creates a fresh payload tree.'
    printf '%s\n' '3. `scripts/check-spk-payload.sh` passes.'
    printf '%s\n' '4. The payload tree is reviewed manually.'
    printf '%s\n' '5. Package lifecycle scripts still do not autostart containers on install or upgrade.'
    printf '%s\n' '6. Runtime data under `/volume1/@lxc/` remains outside the package archive.'
    printf '\n'
    printf '%s\n' '## Proposed package archive layout'
    printf '\n'
    printf '```text\n'
    printf 'INFO\n'
    printf 'conf/privilege\n'
    printf 'scripts/start-stop-status\n'
    printf 'scripts/preinst\n'
    printf 'scripts/postinst\n'
    printf 'scripts/preupgrade\n'
    printf 'scripts/postupgrade\n'
    printf 'scripts/preuninst\n'
    printf 'scripts/postuninst\n'
    printf 'package.tgz\n'
    printf '```\n'
    printf '\n'
    printf '%s\n' '`package.tgz` would contain the reviewed `target/` payload from the dry-run tree.'
    printf '\n'
    printf '%s\n' '## Future manual build commands'
    printf '\n'
    printf '%s\n' 'These commands are intentionally documented, not executed by this script:'
    printf '\n'
    printf '```sh\n'
    printf 'sh scripts/assemble-spk-payload.sh --package %s\n' "$package_name"
    printf 'sh scripts/check-spk-payload.sh --payload %s\n' "$payload_dir"
    printf 'cd %s\n' "$payload_dir"
    printf 'tar -czf package.tgz -C target .\n'
    printf 'tar -cf ../../%s-0.1.0-0005.spk INFO conf scripts package.tgz\n' "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' '## Required future checks'
    printf '\n'
    printf '%s\n' '- verify SPK archive contents before install'
    printf '%s\n' '- install only in Virtual DSM first'
    printf '%s\n' '- verify package `status` before package `start`'
    printf '%s\n' '- verify package `stop` removes lifecycle-owned shim and route'
    printf '%s\n' '- keep DSM package autostart disabled until explicitly implemented'
    printf '\n'
    printf '%s\n' 'Result: SPK BUILD PLAN GENERATED. No .spk was built or installed.'
} >"$plan_file"

cat "$plan_file"
