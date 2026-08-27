#!/bin/sh
# Remove a stopped package-created lab container. Dry-run by default.
# Optional backup and deletion require explicit flags.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --name NAME [--package NAME] [--prefix DIRECTORY] [--state-dir DIRECTORY] [--output DIRECTORY] [--backup] [--destroy]"
}

package_name=lxc-on-dsm
prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
output_dir=
name=
backup=0
destroy=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --backup) backup=1; shift ;;
        --destroy) destroy=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$name" ] || { usage >&2; exit 2; }
case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac
case "$prefix" in /volume[0-9]*/@lxc/lab/opt) ;; *) printf 'Unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /volume[0-9]*/@lxc/lab/containers) ;; *) printf 'Unexpected state dir: %s\n' "$state_dir" >&2; exit 2 ;; esac

pkg_var="/var/packages/${package_name}/var"
[ -n "$output_dir" ] || output_dir="${pkg_var}/artifacts"
case "$output_dir" in
    /var/packages/"${package_name}"/var/artifacts|/volume[0-9]*/@appdata/"${package_name}"/artifacts|artifacts|artifacts/*) ;;
    *) printf 'Unexpected output directory: %s\n' "$output_dir" >&2; exit 2 ;;
esac

if [ "$backup" -eq 1 ] || [ "$destroy" -eq 1 ]; then
    [ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged container backup/remove requires uid=0.' >&2; exit 1; }
fi

PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib:${prefix}/lib64:${LD_LIBRARY_PATH:-}"
LXC_CONFIG_PATH="$state_dir"
export PATH LD_LIBRARY_PATH LXC_CONFIG_PATH

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"
runtime_state="${container_dir}/packaged-start-state.env"

case "$container_dir" in
    "$state_dir"/*) ;;
    *) printf 'Refusing unsafe container path: %s\n' "$container_dir" >&2; exit 2 ;;
esac

[ -d "$container_dir" ] || { printf 'Missing container directory: %s\n' "$container_dir" >&2; exit 1; }
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Refusing to remove running container: %s\n' "$name" >&2
    exit 1
fi

network_type=$(sed -n 's/^lxc\.net\.0\.type = //p' "$config_file" | sed -n '1p')
autostart=$(sed -n 's/^lxc\.start\.auto = //p' "$config_file" | sed -n '1p')

printf '%s\n' '# Packaged LXC container remove plan'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'backup=%s\n' "$backup"
printf 'destroy=%s\n' "$destroy"
printf 'container=%s\n' "$name"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'container_dir=%s\n' "$container_dir"
printf 'rootfs=%s\n' "$rootfs_dir"
printf 'config=%s\n' "$config_file"
printf 'network_type=%s\n' "${network_type:-unknown}"
printf 'autostart=%s\n' "${autostart:-unknown}"
printf 'runtime_state=%s\n' "$runtime_state"
printf 'output=%s\n' "$output_dir"
printf '\n'

if [ "$backup" -ne 1 ] && [ "$destroy" -ne 1 ]; then
    printf '%s\n' 'Result: PACKAGED CONTAINER REMOVE DRY RUN COMPLETE. No files were removed. No container was started.'
    exit 0
fi

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_file=

if [ "$backup" -eq 1 ]; then
    backup_file="${output_dir}/lxc-container-backup-${name}-${stamp}.tar.gz"
    case "$backup_file" in
        "$output_dir"/lxc-container-backup-"$name"-*.tar.gz) ;;
        *) printf 'Refusing unsafe backup path: %s\n' "$backup_file" >&2; exit 2 ;;
    esac
    tar -czf "$backup_file" -C "$state_dir" "$name"
fi

removed=NO
if [ "$destroy" -eq 1 ]; then
    if [ -e "$runtime_state" ]; then
        printf 'Refusing to destroy while runtime state file exists: %s\n' "$runtime_state" >&2
        exit 1
    fi
    rm -rf "$container_dir"
    removed=YES
fi

printf '%s\n' '# Packaged LXC container remove summary'
printf '\n'
printf 'container=%s\n' "$name"
[ -z "$backup_file" ] || printf 'backup_file=%s\n' "$backup_file"
printf 'removed=%s\n' "$removed"
printf '\n'

if [ "$destroy" -eq 1 ]; then
    [ ! -e "$container_dir" ] || { printf 'Container directory still exists: %s\n' "$container_dir" >&2; exit 1; }
    printf '%s\n' 'Result: PACKAGED CONTAINER REMOVED. Container rootfs/config were deleted after explicit --destroy.'
else
    printf '%s\n' 'Result: PACKAGED CONTAINER BACKED UP. No files were removed. No container was started.'
fi
