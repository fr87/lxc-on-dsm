#!/bin/sh
# Execute a command inside a running package-created lab container.
# Dry-run by default. Command arguments are passed directly to lxc-attach.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --name NAME [--package NAME] [--prefix DIRECTORY] [--state-dir DIRECTORY] [--run] [-- COMMAND [ARG...]]"
}

package_name=lxc-on-dsm
prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
name=
run=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --run) run=1; shift ;;
        --) shift; break ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$name" ] || { usage >&2; exit 2; }
case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac
case "$prefix" in /volume[0-9]*/@lxc/lab/opt) ;; *) printf 'Unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /volume[0-9]*/@lxc/lab/containers) ;; *) printf 'Unexpected state dir: %s\n' "$state_dir" >&2; exit 2 ;; esac

PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib:${prefix}/lib64:${LD_LIBRARY_PATH:-}"
LXC_CONFIG_PATH="$state_dir"
export PATH LD_LIBRARY_PATH LXC_CONFIG_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
rootfs_dir="${container_dir}/rootfs"

[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }
command -v lxc-info >/dev/null 2>&1 || { printf 'Missing lxc-info command\n' >&2; exit 1; }
command -v lxc-attach >/dev/null 2>&1 || { printf 'Missing lxc-attach command\n' >&2; exit 1; }

if [ "$#" -eq 0 ]; then
    set -- /bin/sh
fi

printf '%s\n' '# Packaged LXC container exec plan'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'run=%s\n' "$run"
printf 'container=%s\n' "$name"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'command='
first=1
for arg in "$@"; do
    if [ "$first" -eq 1 ]; then
        first=0
    else
        printf ' '
    fi
    printf '%s' "$arg"
done
printf '\n\n'

if [ "$run" -ne 1 ]; then
    printf '%s\n' 'Result: PACKAGED CONTAINER EXEC DRY RUN COMPLETE. No command was executed in the container.'
    exit 0
fi

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged container exec requires uid=0.' >&2; exit 1; }
if ! lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is not running, refusing exec: %s\n' "$name" >&2
    exit 1
fi

printf '%s\n' '# Packaged LXC container exec output'
printf '\n'
lxc-attach -P "$state_dir" -n "$name" -- "$@"
printf '\n%s\n' 'Result: PACKAGED CONTAINER EXEC COMPLETE.'
