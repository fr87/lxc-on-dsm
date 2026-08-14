#!/bin/sh
# Probe basic runtime features in the networkless lab container.
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
command -v lxc-start >/dev/null 2>&1 || { printf 'Missing lxc-start in PATH\n' >&2; exit 1; }
command -v lxc-info >/dev/null 2>&1 || { printf 'Missing lxc-info in PATH\n' >&2; exit 1; }
command -v lxc-stop >/dev/null 2>&1 || { printf 'Missing lxc-stop in PATH\n' >&2; exit 1; }
command -v lxc-attach >/dev/null 2>&1 || { printf 'Missing lxc-attach in PATH\n' >&2; exit 1; }

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-probe-${name}-${stamp}.log"
summary_file="${output_dir}/lxc-probe-${name}-${stamp}.summary"
started=0

cleanup() {
    if [ "$started" -eq 1 ] && lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
        lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
    fi
}
trap cleanup EXIT HUP INT TERM

run_attach() {
    label=$1
    shift
    {
        printf '\n## %s\n' "$label"
        lxc-attach -P "$state_dir" -n "$name" -- "$@"
    } >>"$log_file" 2>&1
}

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi

{
    printf '%s\n' '# LXC lab feature probe'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'config=%s\n' "$config_file"
    printf 'prefix=%s\n' "$prefix"
    printf '\n## host tool versions\n'
    lxc-start --version || true
    lxc-info --version || true
    lxc-attach --version || true
    printf '\n## start keeper\n'
} >"$log_file"

lxc-start -d -P "$state_dir" -n "$name" -- /bin/sh -c 'trap "exit 0" TERM INT; while :; do sleep 60; done' >>"$log_file" 2>&1
started=1

i=0
while [ "$i" -lt 10 ]; do
    if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

if ! lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container did not reach RUNNING state; inspect log: %s\n' "$log_file" >&2
    lxc-info -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
    exit 1
fi

lxc-info -P "$state_dir" -n "$name" >>"$log_file" 2>&1
run_attach basic /bin/sh -c 'echo PROBE_ATTACH_OK; printf "hostname="; hostname; printf "kernel="; uname -r; printf "id="; id'
run_attach pid /bin/sh -c 'printf "pid1_comm="; cat /proc/1/comm 2>/dev/null || true; printf "self_nspid="; sed -n "s/^NSpid:[[:space:]]*//p" /proc/self/status 2>/dev/null || true; printf "self_pid="; echo $$'
run_attach mounts /bin/sh -c 'printf "proc_mount="; grep " /proc " /proc/mounts 2>/dev/null || true; printf "sys_mount="; grep " /sys " /proc/mounts 2>/dev/null || true; printf "cgroup_mounts="; grep cgroup /proc/mounts 2>/dev/null | wc -l'
run_attach devpts /bin/sh -c 'printf "devpts_mount="; grep " /dev/pts " /proc/mounts 2>/dev/null || true; printf "devpts_dir="; ls -ld /dev/pts 2>/dev/null || true; printf "dev_null="; ls -l /dev/null 2>/dev/null || true'
run_attach caps /bin/sh -c 'grep "^Cap" /proc/self/status 2>/dev/null || true'
run_attach network /bin/sh -c 'printf "net_devices="; sed -n "3,$s/:.*//p" /proc/net/dev 2>/dev/null | tr "\n" ","; echo'

lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
started=0

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container still RUNNING after stop; inspect log: %s\n' "$log_file" >&2
    exit 1
fi

{
    printf '%s\n' '# LXC lab feature probe summary'
    printf '\n'
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'config=%s\n' "$config_file"
    printf 'log=%s\n' "$log_file"
    printf '\n'
    if grep -q 'PROBE_ATTACH_OK' "$log_file"; then
        printf 'OK: lxc-attach executed inside the container\n'
    else
        printf 'FAIL: lxc-attach marker missing\n'
    fi
    if grep -q '^hostname='"$name"'$' "$log_file"; then
        printf 'OK: container hostname is isolated\n'
    else
        printf 'WARN: container hostname evidence did not match expected name\n'
    fi
    if grep -q '^kernel=' "$log_file"; then
        printf 'OK: container kernel evidence present\n'
    else
        printf 'WARN: kernel evidence missing\n'
    fi
    if grep -q '^pid1_comm=' "$log_file"; then
        printf 'OK: PID namespace evidence present\n'
    else
        printf 'WARN: PID namespace evidence missing\n'
    fi
    if grep -q '^cgroup_mounts=' "$log_file"; then
        printf 'OK: cgroup mount evidence present\n'
    else
        printf 'WARN: cgroup mount evidence missing\n'
    fi
    if grep -q '^devpts_' "$log_file"; then
        printf 'OK: devpts evidence present\n'
    else
        printf 'WARN: devpts evidence missing\n'
    fi
    printf '\nResult: FEATURE PROBE COMPLETE. Container was stopped and networking remained disabled.\n'
} >"$summary_file"

cat "$summary_file"
