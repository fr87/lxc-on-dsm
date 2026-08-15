#!/bin/sh
# Start an empty-network lab container once and collect network evidence.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY [--name NAME] [--state-dir DIRECTORY] [--output DIRECTORY]"
}

prefix=""
name=alpine-netlab
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
grep -q '^lxc\.net\.0\.type = empty$' "$config_file" || {
    printf 'Container is not configured for the empty-network gate: %s\n' "$config_file" >&2
    exit 1
}

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-empty-net-${name}-${stamp}.log"

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

write_probe_commands() {
    printf '%s\n' 'echo EMPTY_NET_PROBE_BEGIN'
    printf '%s\n' 'printf "hostname="; hostname'
    printf '%s\n' 'printf "kernel="; uname -r'
    printf '%s\n' 'printf "net_devices="; sed -n "3,$s/:.*//p" /proc/net/dev 2>/dev/null | tr "\n" ","; echo'
    printf '%s\n' 'printf "routes="; cat /proc/net/route 2>/dev/null | wc -l'
    printf '%s\n' 'printf "ipv6_if="; cat /proc/net/if_inet6 2>/dev/null | wc -l'
    printf '%s\n' 'echo EMPTY_NET_PROBE_END'
    printf '%s\n' 'exit'
}

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi

printf '%s\n' '# LXC empty-network probe'
printf '\n'
printf 'container=%s\n' "$name"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'log=%s\n' "$log_file"
printf '\n'

{
    printf '%s\n' '# LXC empty-network probe'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'config=%s\n' "$config_file"
    printf '\n## config network lines\n'
    grep -E '^lxc\.net\.|^lxc\.start\.auto' "$config_file" || true
    printf '\n## foreground evidence\n'
} >"$log_file"

if ! write_probe_commands | lxc-start -F -P "$state_dir" -n "$name" >>"$log_file" 2>&1; then
    fail_with_log "Empty-network foreground probe failed; inspect log: $log_file"
fi

if ! grep -q 'EMPTY_NET_PROBE_BEGIN' "$log_file" || ! grep -q 'EMPTY_NET_PROBE_END' "$log_file"; then
    fail_with_log "Empty-network probe markers missing; inspect log: $log_file"
fi

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container still RUNNING after empty-network probe; stopping: %s\n' "$name" >&2
    lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
fi

printf '%s\n' '# LXC empty-network probe summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'log=%s\n' "$log_file"
printf '\n'
grep -E 'EMPTY_NET_PROBE_|^hostname=|^kernel=|^net_devices=|^routes=|^ipv6_if=' "$log_file"
printf '\nResult: EMPTY NETWORK PROBE COMPLETE. No host interface or bridge was configured.\n'
