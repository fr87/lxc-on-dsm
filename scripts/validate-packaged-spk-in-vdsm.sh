#!/bin/sh
# Validate a runtime-bundled SPK on a Virtual DSM lab host.
#
# This script is intentionally explicit. It does not install packages, restore
# runtimes, create containers or start containers unless the corresponding flag
# is passed. It is meant for Virtual DSM lab validation, not for unattended use
# on a productive DSM host.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --spk FILE [--package NAME] [--container NAME] [--prefix DIRECTORY] [--state-dir DIRECTORY] [--output DIRECTORY] [--archive-checker FILE] [--install-package] [--restore-runtime] [--backup-existing-runtime] [--create-container] [--smoke]"
}

package_name=lxc-on-dsm
container_name=alpine-from-spk
prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
output_dir=artifacts
spk_file=
archive_checker=scripts/check-spk-archive.sh
install_package=0
restore_runtime=0
backup_existing_runtime=0
create_container=0
smoke=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --spk) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; spk_file=$2; shift 2 ;;
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --container) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; container_name=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --archive-checker) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; archive_checker=$2; shift 2 ;;
        --install-package) install_package=1; shift ;;
        --restore-runtime) restore_runtime=1; shift ;;
        --backup-existing-runtime) backup_existing_runtime=1; shift ;;
        --create-container) create_container=1; shift ;;
        --smoke) smoke=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$spk_file" ] || { usage >&2; exit 2; }
[ -r "$spk_file" ] || { printf 'Missing SPK: %s\n' "$spk_file" >&2; exit 1; }
[ -r "$archive_checker" ] || { printf 'Missing archive checker: %s\n' "$archive_checker" >&2; exit 1; }
case "$spk_file" in *.spk) ;; *) printf 'SPK path must end with .spk: %s\n' "$spk_file" >&2; exit 2 ;; esac
case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
case "$container_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$container_name" >&2; exit 2 ;; esac
case "$prefix" in /volume[0-9]*/@lxc/lab/opt) ;; *) printf 'Unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /volume[0-9]*/@lxc/lab/containers) ;; *) printf 'Unexpected state dir: %s\n' "$state_dir" >&2; exit 2 ;; esac
case "$output_dir" in /*|artifacts|artifacts/*) ;; *) printf 'Output must be absolute or below artifacts/: %s\n' "$output_dir" >&2; exit 2 ;; esac

if [ "$install_package" -eq 1 ] || [ "$restore_runtime" -eq 1 ] || [ "$backup_existing_runtime" -eq 1 ] || [ "$create_container" -eq 1 ] || [ "$smoke" -eq 1 ]; then
    [ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Mutating Virtual DSM validation requires uid=0.' >&2; exit 1; }
fi

synopkg_bin=/usr/syno/bin/synopkg
pkg_base="/var/packages/${package_name}"
pkg_target="${pkg_base}/target"
pkg_var="${pkg_base}/var"
pkg_output="${pkg_var}/artifacts"

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
report="${output_dir}/packaged-spk-vdsm-validation-${stamp}.md"

note() {
    printf '%s\n' "$1"
    printf '%s\n' "$1" >>"$report"
}

append_cmd() {
    {
        printf '\n```text\n'
    } | tee -a "$report"
    tmp_cmd="${output_dir}/.packaged-spk-vdsm-validation-cmd.$$"
    set +e
    "$@" >"$tmp_cmd" 2>&1
    cmd_status=$?
    set -e
    cat "$tmp_cmd" | tee -a "$report"
    rm -f "$tmp_cmd"
    {
        printf '\n[exit_status=%s]\n' "$cmd_status"
        printf '```\n'
    } | tee -a "$report"
    return "$cmd_status"
}

runtime_target_nonempty=0
if [ -d "$prefix" ] && find "$prefix" -mindepth 1 -maxdepth 1 -print 2>/dev/null | sed -n '1p' | grep -q .; then
    runtime_target_nonempty=1
fi

container_exists=0
[ ! -e "${state_dir}/${container_name}" ] || container_exists=1

{
    printf '%s\n' '# Packaged SPK Virtual DSM validation'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'package=%s\n' "$package_name"
    printf 'spk=%s\n' "$spk_file"
    printf 'archive_checker=%s\n' "$archive_checker"
    printf 'container=%s\n' "$container_name"
    printf 'prefix=%s\n' "$prefix"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'install_package=%s\n' "$install_package"
    printf 'restore_runtime=%s\n' "$restore_runtime"
    printf 'backup_existing_runtime=%s\n' "$backup_existing_runtime"
    printf 'create_container=%s\n' "$create_container"
    printf 'smoke=%s\n' "$smoke"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- Virtual DSM lab validation only'
    printf '%s\n' '- no physical/productive DSM host should run this script'
    printf '%s\n' '- Package Center start/stop remains outside this validation'
    printf '%s\n' '- networking stays disabled when the default `none` container is used'
} >"$report"

printf '%s\n' '# Packaged SPK Virtual DSM validation'
printf '\n'
printf 'report=%s\n' "$report"
printf 'spk=%s\n' "$spk_file"
printf 'archive_checker=%s\n' "$archive_checker"
printf 'container=%s\n' "$container_name"
printf '\n'

note ''
note '## Archive gate'
append_cmd sh "$archive_checker" --spk "$spk_file" --require-runtime-bundle --require-alpine-image

if [ "$install_package" -eq 1 ]; then
    [ -x "$synopkg_bin" ] || { printf 'Missing DSM synopkg: %s\n' "$synopkg_bin" >&2; exit 1; }
    note ''
    note '## Package install/upgrade'
    append_cmd "$synopkg_bin" install "$spk_file"
else
    note ''
    note '## Package install/upgrade'
    note 'SKIP: --install-package was not passed.'
fi

note ''
note '## Installed package state'
if [ -x "$synopkg_bin" ]; then
    append_cmd "$synopkg_bin" status "$package_name" || true
else
    note "WARN: DSM synopkg not available at ${synopkg_bin}"
fi
[ -r "${pkg_target}/ui/status.json" ] || { printf 'Missing installed UI status manifest: %s\n' "${pkg_target}/ui/status.json" >&2; exit 1; }
append_cmd cat "${pkg_target}/ui/status.json"
grep -q '"runtime_bundle_packaged": true' "${pkg_target}/ui/status.json" || { printf '%s\n' 'Installed status.json does not report packaged runtime.' >&2; exit 1; }
grep -q '"alpine_image_packaged": true' "${pkg_target}/ui/status.json" || { printf '%s\n' 'Installed status.json does not report packaged Alpine image.' >&2; exit 1; }

if [ "$restore_runtime" -eq 1 ]; then
    if [ "$runtime_target_nonempty" -eq 1 ]; then
        if [ "$backup_existing_runtime" -ne 1 ]; then
            printf 'Runtime target already exists and is not empty: %s\n' "$prefix" >&2
            printf '%s\n' 'Pass --backup-existing-runtime to move it aside before restore.' >&2
            exit 1
        fi
        backup="${prefix}.backup-${stamp}"
        [ ! -e "$backup" ] || { printf 'Backup target already exists: %s\n' "$backup" >&2; exit 1; }
        note ''
        note '## Existing runtime backup'
        append_cmd mv "$prefix" "$backup"
    fi
    note ''
    note '## Packaged runtime restore'
    append_cmd sh "${pkg_target}/scripts/install-packaged-runtime.sh" --output "$pkg_output" --install
else
    note ''
    note '## Packaged runtime restore'
    note 'SKIP: --restore-runtime was not passed.'
fi

note ''
note '## Runtime verification'
append_cmd sh scripts/verify-lxc-install.sh --prefix "$prefix"

if [ "$create_container" -eq 1 ]; then
    if [ "$container_exists" -eq 1 ]; then
        printf 'Container already exists: %s\n' "${state_dir}/${container_name}" >&2
        exit 1
    fi
    note ''
    note '## Packaged container create'
    append_cmd sh "${pkg_target}/scripts/create-packaged-container.sh" --name "$container_name" --prefix "$prefix" --state-dir "$state_dir" --network-type none --create
else
    note ''
    note '## Packaged container create'
    note 'SKIP: --create-container was not passed.'
fi

note ''
note '## Container config verification'
append_cmd sh scripts/verify-lxc-runtime.sh --prefix "$prefix" --state-dir "$state_dir" --name "$container_name"

if [ "$smoke" -eq 1 ]; then
    note ''
    note '## Networkless smoke test'
    append_cmd sh scripts/run-lab-smoke-test.sh --prefix "$prefix" --state-dir "$state_dir" --name "$container_name" --output "$output_dir"
else
    note ''
    note '## Networkless smoke test'
    note 'SKIP: --smoke was not passed.'
fi

note ''
note 'Result: PACKAGED SPK VDSM VALIDATION PASSED.'
printf '\nResult: PACKAGED SPK VDSM VALIDATION PASSED.\n'
