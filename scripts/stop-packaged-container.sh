#!/bin/sh
# Stop a package-created lab container. Read/write scope is limited to package lab state.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --name NAME [--package NAME] [--prefix DIRECTORY] [--state-dir DIRECTORY] [--output DIRECTORY]"
}

package_name=lxc-on-dsm
prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
output_dir=
name=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
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

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged container stop requires uid=0.' >&2; exit 1; }

PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib:${prefix}/lib64:${LD_LIBRARY_PATH:-}"
LXC_CONFIG_PATH="$state_dir"
export PATH LD_LIBRARY_PATH LXC_CONFIG_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
runtime_state="${container_dir}/packaged-start-state.env"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-packaged-stop-${name}-${stamp}.log"

{
    printf '%s\n' '# Packaged LXC container stop'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'runtime_state=%s\n' "$runtime_state"
    printf '\n## stop\n'
} >"$log_file"

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
fi

container_stopped=NO
if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    container_stopped=NO
else
    container_stopped=YES
fi

if [ -e "$runtime_state" ]; then
    mv -f "$runtime_state" "${runtime_state}.previous.${stamp}"
fi

printf '%s\n' '# Packaged LXC container stop summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'container_stopped=%s\n' "$container_stopped"
printf 'log=%s\n' "$log_file"
printf '\n'

if [ "$container_stopped" = YES ]; then
    printf '%s\n' 'Result: PACKAGED CONTAINER STOPPED.'
else
    printf '%s\n' 'Result: PACKAGED CONTAINER STOP INCOMPLETE. Inspect log and host state.'
    exit 1
fi
