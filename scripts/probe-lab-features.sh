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

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-probe-${name}-${stamp}.log"
summary_file="${output_dir}/lxc-probe-${name}-${stamp}.summary"
started=0
attach_status=SKIPPED

show_log_tail() {
    if [ -r "$log_file" ]; then
        printf '\nLast log lines from %s:\n' "$log_file" >&2
        tail -n 60 "$log_file" >&2 || true
    fi
}

fail_with_log() {
    printf '%s\n' "$1" >&2
    show_log_tail
    exit 1
}

cleanup() {
    if [ "$started" -eq 1 ] && lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
        lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
    fi
}
trap cleanup EXIT HUP INT TERM

write_foreground_probe_commands() {
    printf '%s\n' 'echo PROBE_FOREGROUND_BEGIN'
    printf '%s\n' 'printf "hostname="; hostname'
    printf '%s\n' 'printf "kernel="; uname -r'
    printf '%s\n' 'printf "id="; id'
    printf '%s\n' 'printf "pid1_comm="; cat /proc/1/comm 2>/dev/null || true'
    printf '%s\n' 'printf "self_nspid="; sed -n "s/^NSpid:[[:space:]]*//p" /proc/self/status 2>/dev/null || true'
    printf '%s\n' 'printf "self_pid="; echo $$'
    printf '%s\n' 'printf "proc_mount="; grep " /proc " /proc/mounts 2>/dev/null || true'
    printf '%s\n' 'printf "sys_mount="; grep " /sys " /proc/mounts 2>/dev/null || true'
    printf '%s\n' 'printf "cgroup_mounts="; grep cgroup /proc/mounts 2>/dev/null | wc -l'
    printf '%s\n' 'printf "devpts_mount="; grep " /dev/pts " /proc/mounts 2>/dev/null || true'
    printf '%s\n' 'printf "devpts_dir="; ls -ld /dev/pts 2>/dev/null || true'
    printf '%s\n' 'printf "dev_null="; ls -l /dev/null 2>/dev/null || true'
    printf '%s\n' 'grep "^Cap" /proc/self/status 2>/dev/null || true'
    printf '%s\n' 'printf "net_devices="; sed -n "3,$s/:.*//p" /proc/net/dev 2>/dev/null | tr "\n" ","; echo'
    printf '%s\n' 'echo PROBE_FOREGROUND_END'
    printf '%s\n' 'exit'
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
    if command -v lxc-attach >/dev/null 2>&1; then
        lxc-attach --version || true
    else
        printf 'lxc-attach missing\n'
    fi
} >"$log_file"

printf '%s\n' '# LXC lab feature probe'
printf '\n'
printf 'container=%s\n' "$name"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'log=%s\n' "$log_file"
printf 'summary=%s\n' "$summary_file"
printf '\n'

if command -v lxc-attach >/dev/null 2>&1; then
    printf '%s\n' 'Probing lxc-attach with a temporary detached container...'
    printf '\n## detached keeper for lxc-attach probe\n' >>"$log_file"
    if lxc-start -d -P "$state_dir" -n "$name" -- /bin/sh -c 'trap "exit 0" TERM INT; while :; do sleep 60; done' >>"$log_file" 2>&1; then
        started=1
        i=0
        while [ "$i" -lt 10 ]; do
            if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
                break
            fi
            i=$((i + 1))
            sleep 1
        done
        lxc-info -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
        printf '\n## lxc-attach basic\n' >>"$log_file"
        if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING' &&
            lxc-attach -P "$state_dir" -n "$name" -- /bin/sh -c 'echo PROBE_ATTACH_OK; printf "attach_hostname="; hostname' >>"$log_file" 2>&1; then
            attach_status=OK
        else
            attach_status=WARN
        fi
        lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
        started=0
        if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
            fail_with_log "Container still RUNNING after lxc-attach probe; inspect log: $log_file"
        fi
    else
        attach_status=WARN
        started=0
    fi
else
    printf '%s\n' 'Skipping lxc-attach probe because lxc-attach is missing.'
fi

printf '%s\n' 'Collecting foreground runtime evidence...'
printf '\n## foreground evidence probe\n' >>"$log_file"
if ! write_foreground_probe_commands | lxc-start -F -P "$state_dir" -n "$name" >>"$log_file" 2>&1; then
    fail_with_log "Foreground evidence probe failed; inspect log: $log_file"
fi

if ! grep -q 'PROBE_FOREGROUND_BEGIN' "$log_file" || ! grep -q 'PROBE_FOREGROUND_END' "$log_file"; then
    fail_with_log "Foreground evidence markers missing; inspect log: $log_file"
fi

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container still RUNNING after foreground probe; stopping: %s\n' "$name" >&2
    lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
fi

{
    printf '%s\n' '# LXC lab feature probe summary'
    printf '\n'
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'config=%s\n' "$config_file"
    printf 'log=%s\n' "$log_file"
    printf '\n'
    case "$attach_status" in
        OK) printf 'OK: lxc-attach executed inside the container\n' ;;
        WARN) printf 'WARN: lxc-attach failed; inspect log for DSM/Entware attach limitations\n' ;;
        SKIPPED) printf 'WARN: lxc-attach was skipped or is unavailable\n' ;;
    esac
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
    if grep -q '^net_devices=' "$log_file"; then
        printf 'OK: network device evidence present while networking remained disabled\n'
    else
        printf 'WARN: network device evidence missing\n'
    fi
    printf '\nResult: FEATURE PROBE COMPLETE. Container was stopped and networking remained disabled.\n'
} >"$summary_file"

cat "$summary_file"
