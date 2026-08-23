#!/bin/sh
# Start a stopped package-created container once without networking, collect
# evidence, and stop again. Intended for installed SPK lab validation.
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

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged smoke test requires uid=0.' >&2; exit 1; }

PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
grep -q '^lxc\.net\.0\.type = none$' "$config_file" || {
    printf '%s\n' 'Refusing smoke test because container is not configured with lxc.net.0.type = none.' >&2
    exit 1
}
grep -q '^lxc\.start\.auto = 0$' "$config_file" || {
    printf '%s\n' 'Refusing smoke test because container is not configured with lxc.start.auto = 0.' >&2
    exit 1
}

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-packaged-smoke-${name}-${stamp}.log"

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi

printf '%s\n' '# Packaged LXC networkless smoke test'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'container=%s\n' "$name"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'log=%s\n' "$log_file"
printf '\n'

{
    printf '%s\n' 'echo DSM_LXC_PACKAGED_SMOKE_BEGIN'
    printf '%s\n' 'printf "hostname="; hostname'
    printf '%s\n' 'printf "kernel="; uname -r'
    printf '%s\n' 'printf "pid1_comm="; cat /proc/1/comm 2>/dev/null || true'
    printf '%s\n' 'printf "self_nspid="; sed -n "s/^NSpid:[[:space:]]*//p" /proc/self/status 2>/dev/null || true'
    printf '%s\n' 'printf "cgroup_mounts="; grep cgroup /proc/mounts 2>/dev/null | wc -l'
    printf '%s\n' 'printf "net_devices="; sed -n "3,$s/:.*//p" /proc/net/dev 2>/dev/null | tr "\n" ","; echo'
    printf '%s\n' 'echo DSM_LXC_PACKAGED_SMOKE_END'
    printf '%s\n' 'exit'
} | lxc-start -F -P "$state_dir" -n "$name" >"$log_file" 2>&1

if ! grep -q 'DSM_LXC_PACKAGED_SMOKE_BEGIN' "$log_file" || ! grep -q 'DSM_LXC_PACKAGED_SMOKE_END' "$log_file"; then
    printf 'Smoke markers missing; inspect log: %s\n' "$log_file" >&2
    lxc-info -P "$state_dir" -n "$name" || true
    exit 1
fi

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container still running after smoke command; stopping: %s\n' "$name" >&2
    lxc-stop -P "$state_dir" -n "$name" || true
fi

lxc-info -P "$state_dir" -n "$name"
printf '\nSmoke evidence:\n'
grep -E 'DSM_LXC_PACKAGED_SMOKE_|^hostname=|^kernel=|^pid1_comm=|^self_nspid=|^cgroup_mounts=|^net_devices=' "$log_file"
printf '\nResult: PACKAGED SMOKE TEST PASSED. Container was started and stopped without networking.\n'
