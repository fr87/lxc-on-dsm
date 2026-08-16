#!/bin/sh
# Create a recovery evidence bundle for the installed DSM lab package.
# Does not start/stop containers or include rootfs data.
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

stamp=$(date -u +%Y%m%dT%H%M%SZ)
bundle_name="recovery-bundle-${package_name}-${stamp}"
bundle_dir="${output_dir}/${bundle_name}"
archive_file="${output_dir}/${bundle_name}.tar.gz"

[ ! -e "$bundle_dir" ] || { printf 'Bundle directory already exists: %s\n' "$bundle_dir" >&2; exit 1; }
[ ! -e "$archive_file" ] || { printf 'Bundle archive already exists: %s\n' "$archive_file" >&2; exit 1; }

base="/var/packages/${package_name}"
target="${base}/target"
conf_dir="${base}/conf"
script_dir="${base}/scripts"
helper="${target}/scripts/lxc-on-dsm-root-helper.sh"

mkdir -p "$bundle_dir/package" "$bundle_dir/profile" "$bundle_dir/container" "$bundle_dir/observations"

copy_if_readable() {
    src=$1
    dst=$2
    if [ -r "$src" ]; then
        mkdir -p "${bundle_dir}/$(dirname "$dst")"
        cp "$src" "${bundle_dir}/${dst}"
        printf 'COPIED: %s -> %s\n' "$src" "$dst" >>"${bundle_dir}/MANIFEST.txt"
    else
        printf 'MISSING: %s\n' "$src" >>"${bundle_dir}/MANIFEST.txt"
    fi
}

{
    printf '%s\n' '# DSM LXC recovery bundle manifest'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'package=%s\n' "$package_name"
    printf 'profile=%s\n' "$profile_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '%s\n' '- evidence bundle only'
    printf '%s\n' '- does not start or stop containers'
    printf '%s\n' '- does not create interfaces or routes'
    printf '%s\n' '- does not include container rootfs data'
    printf '\n'
    printf '%s\n' '## Copied files'
} >"${bundle_dir}/MANIFEST.txt"

copy_if_readable "${base}/INFO" "package/INFO"
copy_if_readable "${conf_dir}/privilege" "package/conf/privilege"
copy_if_readable "${conf_dir}/resource" "package/conf/resource"
copy_if_readable "${conf_dir}/resource.own" "package/conf/resource.own"
copy_if_readable "${script_dir}/start-stop-status" "package/scripts/start-stop-status"
copy_if_readable "${target}/scripts/lxc-on-dsm-root-helper.sh" "package/target/scripts/lxc-on-dsm-root-helper.sh"
copy_if_readable "${target}/scripts/start-macvlan-profile.sh" "package/target/scripts/start-macvlan-profile.sh"
copy_if_readable "${target}/scripts/stop-macvlan-profile.sh" "package/target/scripts/stop-macvlan-profile.sh"
copy_if_readable "${target}/scripts/doctor-macvlan-profile.sh" "package/target/scripts/doctor-macvlan-profile.sh"
copy_if_readable "${target}/scripts/verify-macvlan-profile.sh" "package/target/scripts/verify-macvlan-profile.sh"
copy_if_readable "${target}/scripts/prepare-package-access.sh" "package/target/scripts/prepare-package-access.sh"
copy_if_readable "$profile_file" "profile/lab-macvlan.env"

{
    printf '%s\n' '# Package path observations'
    printf '\n'
    ls -ld "$base" "$target" "${base}/etc" "${base}/var" 2>&1 || true
    printf '\n'
    ls -l "$helper" 2>&1 || true
} >"${bundle_dir}/observations/package-paths.txt"

state_dir=
name=
if [ -r "$profile_file" ]; then
    # shellcheck disable=SC1090
    . "$profile_file"
    state_dir=${LXC_LAB_STATE_DIR:-}
    name=${LXC_LAB_CONTAINER:-}
fi

if [ -n "$state_dir" ] && [ -n "$name" ]; then
    case "$state_dir" in
        /volume[0-9]*/@lxc/lab/containers) ;;
        *) printf 'WARN: refusing unexpected state dir: %s\n' "$state_dir" >>"${bundle_dir}/MANIFEST.txt"; state_dir= ;;
    esac
    case "$name" in
        *[!A-Za-z0-9_.-]*|'') printf 'WARN: refusing invalid container name: %s\n' "$name" >>"${bundle_dir}/MANIFEST.txt"; name= ;;
    esac
fi

if [ -n "$state_dir" ] && [ -n "$name" ]; then
    container_dir="${state_dir}/${name}"
    copy_if_readable "${container_dir}/config" "container/${name}/config"
    if [ -r "${container_dir}/lifecycle-state.env" ]; then
        copy_if_readable "${container_dir}/lifecycle-state.env" "container/${name}/lifecycle-state.env"
    fi
    {
        printf '%s\n' '# Container path observations'
        printf '\n'
        ls -ld "$state_dir" "$container_dir" "${container_dir}/rootfs" 2>&1 || true
        printf '\n'
        find "$container_dir" -maxdepth 1 -type f -name 'lifecycle-state.env*' -print 2>/dev/null | sort || true
    } >"${bundle_dir}/observations/container-paths.txt"
fi

if [ -x "$helper" ]; then
    sh "$helper" --dry-run status --profile "$profile_file" >"${bundle_dir}/observations/helper-dry-run-status.txt" 2>&1 || true
    sh "$helper" status --profile "$profile_file" >"${bundle_dir}/observations/helper-status.txt" 2>&1 || true
fi

if [ -x scripts/check-package-recovery.sh ]; then
    sh scripts/check-package-recovery.sh --profile "$profile_file" --output "$bundle_dir/observations" >"${bundle_dir}/observations/package-recovery-check.txt" 2>&1 || true
fi

if command -v sha256sum >/dev/null 2>&1; then
    (
        cd "$bundle_dir"
        find . -type f ! -name SHA256SUMS -print | sort | xargs sha256sum
    ) >"${bundle_dir}/SHA256SUMS"
fi

tar -czf "$archive_file" -C "$output_dir" "$bundle_name"

printf '%s\n' '# DSM LXC recovery bundle'
printf '\n'
printf 'bundle_dir=%s\n' "$bundle_dir"
printf 'archive=%s\n' "$archive_file"
printf '\n'
printf '%s\n' 'Result: RECOVERY BUNDLE CREATED. No container or network state was changed.'
