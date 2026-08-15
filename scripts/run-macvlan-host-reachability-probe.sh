#!/bin/sh
# Probe DSM host -> macvlan container reachability.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY [--name NAME] [--state-dir DIRECTORY] [--output DIRECTORY]"
}

prefix=""
name=alpine-macvlanlab
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
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }
grep -q '^lxc\.net\.0\.type = macvlan$' "$config_file" || {
    printf 'Container is not configured for the macvlan host reachability gate: %s\n' "$config_file" >&2
    exit 1
}
parent_if=$(sed -n 's/^lxc\.net\.0\.link = //p' "$config_file" | sed -n '1p')
[ -n "$parent_if" ] || { printf 'Missing lxc.net.0.link parent interface in config: %s\n' "$config_file" >&2; exit 1; }
command -v ip >/dev/null 2>&1 || { printf 'Missing host ip command\n' >&2; exit 1; }
command -v ping >/dev/null 2>&1 || { printf 'Missing host ping command\n' >&2; exit 1; }
ip link show "$parent_if" >/dev/null 2>&1 || {
    printf 'Parent interface does not exist, refusing to start container: %s\n' "$parent_if" >&2
    exit 1
}

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-macvlan-host-${name}-${stamp}.log"
evidence_rel=tmp/dsm-lxc-macvlan-host-probe.env
evidence_file="${rootfs_dir}/${evidence_rel}"
evidence_old="${evidence_file}.previous"
started=0

show_log_tail() {
    if [ -r "$log_file" ]; then
        printf '\nLast log lines from %s:\n' "$log_file" >&2
        tail -n 100 "$log_file" >&2 || true
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

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi

if [ -e "$evidence_file" ]; then
    mv "$evidence_file" "$evidence_old"
fi

printf '%s\n' '# LXC macvlan host reachability probe'
printf '\n'
printf 'container=%s\n' "$name"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'parent_if=%s\n' "$parent_if"
printf 'evidence=%s\n' "$evidence_file"
printf 'log=%s\n' "$log_file"
printf '\n'

{
    printf '%s\n' '# LXC macvlan host reachability probe'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'config=%s\n' "$config_file"
    printf 'parent_if=%s\n' "$parent_if"
    printf 'evidence=%s\n' "$evidence_file"
    printf '\n## config network lines\n'
    grep -E '^lxc\.net\.|^lxc\.start\.auto' "$config_file" || true
    printf '\n## host parent before\n'
    ip -o link show "$parent_if" || true
    printf '\n## detached container start\n'
} >"$log_file"

if ! lxc-start -d -P "$state_dir" -n "$name" -- /bin/sh -c '
    evidence=/tmp/dsm-lxc-macvlan-host-probe.env
    dhcp_status=SKIPPED
    if command -v udhcpc >/dev/null 2>&1; then
        udhcpc -i eth0 -n -q -t 3 -T 3 >/tmp/udhcpc-host-probe.log 2>&1 && dhcp_status=OK || dhcp_status=FAIL
    fi
    ip_addr=$(ip -4 -o addr show dev eth0 2>/dev/null | awk "{print \$4; exit}")
    ip_plain=${ip_addr%%/*}
    gateway=$(ip route 2>/dev/null | awk "/^default / {print \$3; exit}")
    {
        printf "dhcp_status=%s\n" "$dhcp_status"
        printf "ip_addr=%s\n" "$ip_addr"
        printf "ip_plain=%s\n" "$ip_plain"
        printf "gateway=%s\n" "$gateway"
        printf "routes=%s\n" "$(ip route 2>/dev/null | tr "\n" "|")"
        printf "udhcpc_log=%s\n" "$(tr "\n" "|" </tmp/udhcpc-host-probe.log 2>/dev/null || true)"
    } >"$evidence"
    trap "exit 0" TERM INT
    while :; do sleep 60; done
' >>"$log_file" 2>&1; then
    fail_with_log "Detached macvlan host reachability start failed; inspect log: $log_file"
fi
started=1

i=0
while [ "$i" -lt 15 ]; do
    [ -r "$evidence_file" ] && break
    i=$((i + 1))
    sleep 1
done

[ -r "$evidence_file" ] || fail_with_log "Container did not write host reachability evidence: $evidence_file"

cat "$evidence_file" >>"$log_file"
dhcp_status=$(sed -n 's/^dhcp_status=//p' "$evidence_file" | sed -n '1p')
ip_plain=$(sed -n 's/^ip_plain=//p' "$evidence_file" | sed -n '1p')
gateway=$(sed -n 's/^gateway=//p' "$evidence_file" | sed -n '1p')

host_ping=SKIPPED
if [ -n "$ip_plain" ]; then
    if ping -c 1 -W 2 "$ip_plain" >"${output_dir}/host-ping-${name}-${stamp}.log" 2>&1; then
        host_ping=OK
    else
        host_ping=FAIL
    fi
fi

lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
started=0

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    fail_with_log "Container still RUNNING after host reachability probe; inspect log: $log_file"
fi

printf '%s\n' '# LXC macvlan host reachability probe summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'parent_if=%s\n' "$parent_if"
printf 'log=%s\n' "$log_file"
printf '\n'
printf 'dhcp_status=%s\n' "$dhcp_status"
printf 'ip_plain=%s\n' "$ip_plain"
printf 'gateway=%s\n' "$gateway"
printf 'host_ping=%s\n' "$host_ping"
printf '\n'
printf '%s\n' 'Result: MACVLAN HOST REACHABILITY PROBE COMPLETE. Container was stopped.'
