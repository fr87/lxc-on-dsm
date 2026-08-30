#!/bin/sh
# Start the networkless lab container once, collect evidence, and let it stop.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY [--name NAME] [--state-dir DIRECTORY] [--output DIRECTORY]"
}

prefix=""
name=alpine-lab
state_dir=/volume1/@lxc/lab/containers
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { usage >&2; exit 2; }
case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 2 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-smoke-${name}-${stamp}.log"

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi

printf '%s\n' '# LXC lab smoke test'
printf '\n'
printf 'container=%s\n' "$name"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'log=%s\n' "$log_file"
printf '\n'

{
    printf '%s\n' 'echo DSM_LXC_SMOKE_BEGIN'
    printf '%s\n' 'printf "hostname="; hostname'
    printf '%s\n' 'printf "kernel="; uname -r'
    printf '%s\n' 'printf "pid1_comm="; cat /proc/1/comm 2>/dev/null || true'
    printf '%s\n' 'printf "self_nspid="; sed -n "s/^NSpid:[[:space:]]*//p" /proc/self/status 2>/dev/null || true'
    printf '%s\n' 'printf "proc_mount="; grep " /proc " /proc/mounts 2>/dev/null || true'
    printf '%s\n' 'printf "sys_mount="; grep " /sys " /proc/mounts 2>/dev/null || true'
    printf '%s\n' 'printf "cgroup_mounts="; grep cgroup /proc/mounts 2>/dev/null | wc -l'
    printf '%s\n' 'printf "net_devices="; sed -n "3,$s/:.*//p" /proc/net/dev 2>/dev/null | tr "\n" ","; echo'
    printf '%s\n' 'echo DSM_LXC_SMOKE_END'
    printf '%s\n' 'exit'
} | lxc-start -F -P "$state_dir" -n "$name" >"$log_file" 2>&1

if ! grep -q 'DSM_LXC_SMOKE_BEGIN' "$log_file" || ! grep -q 'DSM_LXC_SMOKE_END' "$log_file"; then
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
grep -E 'DSM_LXC_SMOKE_|^hostname=|^kernel=|^pid1_comm=|^self_nspid=|^cgroup_mounts=|^net_devices=' "$log_file"
printf '\nResult: SMOKE TEST PASSED. Container was started and stopped without networking.\n'
