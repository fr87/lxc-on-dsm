#!/bin/sh
# Temporarily create a host-side macvlan shim and test DSM host -> container reachability.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY --host-cidr CIDR [--name NAME] [--state-dir DIRECTORY] [--shim-if IFACE] [--container-ip IP] [--output DIRECTORY]"
}

prefix=
host_cidr=
name=alpine-macvlanlab
state_dir=/volume1/@lxc/lab/containers
shim_if=lxcshim0
container_ip_override=
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --host-cidr) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; host_cidr=$2; shift 2 ;;
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --shim-if) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; shim_if=$2; shift 2 ;;
        --container-ip) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; container_ip_override=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { usage >&2; exit 2; }
[ -n "$host_cidr" ] || { printf 'Missing required --host-cidr. Choose a free LAN IP/CIDR for the temporary shim.\n' >&2; usage >&2; exit 2; }
case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 2 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac
case "$shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid shim interface: %s\n' "$shim_if" >&2; exit 2 ;; esac
case "$host_cidr" in *[!A-Za-z0-9_./:-]*|'') printf 'Invalid host CIDR: %s\n' "$host_cidr" >&2; exit 2 ;; esac
case "$container_ip_override" in *[!A-Za-z0-9_.:-]*) printf 'Invalid container IP: %s\n' "$container_ip_override" >&2; exit 2 ;; esac
if [ ${#shim_if} -gt 15 ]; then
    printf 'Shim interface name is too long for Linux interfaces: %s\n' "$shim_if" >&2
    exit 2
fi

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }
grep -q '^lxc\.net\.0\.type = macvlan$' "$config_file" || {
    printf 'Container is not configured for the macvlan host shim gate: %s\n' "$config_file" >&2
    exit 1
}
parent_if=$(sed -n 's/^lxc\.net\.0\.link = //p' "$config_file" | sed -n '1p')
[ -n "$parent_if" ] || { printf 'Missing lxc.net.0.link parent interface in config: %s\n' "$config_file" >&2; exit 1; }
case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface in config: %s\n' "$parent_if" >&2; exit 1 ;; esac
command -v ip >/dev/null 2>&1 || { printf 'Missing host ip command\n' >&2; exit 1; }
command -v ping >/dev/null 2>&1 || { printf 'Missing host ping command\n' >&2; exit 1; }
ip link show "$parent_if" >/dev/null 2>&1 || {
    printf 'Parent interface does not exist, refusing to start container: %s\n' "$parent_if" >&2
    exit 1
}
if ip link show "$shim_if" >/dev/null 2>&1; then
    printf 'Shim interface already exists, refusing to take over: %s\n' "$shim_if" >&2
    exit 1
fi
if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-macvlan-host-shim-${name}-${stamp}.log"
evidence_rel=tmp/dsm-lxc-macvlan-host-shim-probe.env
evidence_file="${rootfs_dir}/${evidence_rel}"
evidence_old="${evidence_file}.previous"
started=0
shim_created=0
route_added=0
container_ip=

show_log_tail() {
    if [ -r "$log_file" ]; then
        printf '\nLast log lines from %s:\n' "$log_file" >&2
        tail -n 120 "$log_file" >&2 || true
    fi
}

fail_with_log() {
    printf '%s\n' "$1" >&2
    show_log_tail
    exit 1
}

cleanup() {
    if [ "$route_added" -eq 1 ] && [ -n "$container_ip" ]; then
        ip route del "${container_ip}/32" dev "$shim_if" >>"$log_file" 2>&1 || true
    fi
    if [ "$shim_created" -eq 1 ]; then
        ip link set "$shim_if" down >>"$log_file" 2>&1 || true
        ip link del "$shim_if" >>"$log_file" 2>&1 || true
    fi
    if [ "$started" -eq 1 ] && lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
        lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
    fi
}
trap cleanup EXIT HUP INT TERM

if [ -e "$evidence_file" ]; then
    mv "$evidence_file" "$evidence_old"
fi

printf '%s\n' '# LXC macvlan host shim probe'
printf '\n'
printf 'container=%s\n' "$name"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'parent_if=%s\n' "$parent_if"
printf 'shim_if=%s\n' "$shim_if"
printf 'host_cidr=%s\n' "$host_cidr"
printf 'container_ip_override=%s\n' "$container_ip_override"
printf 'evidence=%s\n' "$evidence_file"
printf 'log=%s\n' "$log_file"
printf '\n'

{
    printf '%s\n' '# LXC macvlan host shim probe'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'config=%s\n' "$config_file"
    printf 'parent_if=%s\n' "$parent_if"
    printf 'shim_if=%s\n' "$shim_if"
    printf 'host_cidr=%s\n' "$host_cidr"
    printf 'container_ip_override=%s\n' "$container_ip_override"
    printf '\n## config network lines\n'
    grep -E '^lxc\.net\.|^lxc\.start\.auto' "$config_file" || true
    printf '\n## host parent before\n'
    ip -o addr show "$parent_if" || true
    printf '\n## detached container start\n'
} >"$log_file"

if ! lxc-start -d -P "$state_dir" -n "$name" -- /bin/sh -c '
    evidence=/tmp/dsm-lxc-macvlan-host-shim-probe.env
    dhcp_status=SKIPPED
    if command -v udhcpc >/dev/null 2>&1; then
        udhcpc -i eth0 -n -q -t 3 -T 3 >/tmp/udhcpc-host-shim-probe.log 2>&1 && dhcp_status=OK || dhcp_status=FAIL
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
        printf "udhcpc_log=%s\n" "$(tr "\n" "|" </tmp/udhcpc-host-shim-probe.log 2>/dev/null || true)"
    } >"$evidence"
    trap "exit 0" TERM INT
    while :; do sleep 60; done
' >>"$log_file" 2>&1; then
    fail_with_log "Detached macvlan host shim start failed; inspect log: $log_file"
fi
started=1

i=0
while [ "$i" -lt 15 ]; do
    [ -r "$evidence_file" ] && break
    i=$((i + 1))
    sleep 1
done

[ -r "$evidence_file" ] || fail_with_log "Container did not write host shim evidence: $evidence_file"

cat "$evidence_file" >>"$log_file"
dhcp_status=$(sed -n 's/^dhcp_status=//p' "$evidence_file" | sed -n '1p')
detected_ip=$(sed -n 's/^ip_plain=//p' "$evidence_file" | sed -n '1p')
gateway=$(sed -n 's/^gateway=//p' "$evidence_file" | sed -n '1p')

container_ip=${container_ip_override:-$detected_ip}
[ -n "$container_ip" ] || fail_with_log "Container IP is empty; cannot add a host shim route"

printf '\n## host shim setup\n' >>"$log_file"
ip link add "$shim_if" link "$parent_if" type macvlan mode bridge >>"$log_file" 2>&1 || fail_with_log "Host shim creation failed; inspect log: $log_file"
shim_created=1
ip addr add "$host_cidr" dev "$shim_if" >>"$log_file" 2>&1 || fail_with_log "Host shim address assignment failed; inspect log: $log_file"
ip link set "$shim_if" up >>"$log_file" 2>&1 || fail_with_log "Host shim activation failed; inspect log: $log_file"
ip route add "${container_ip}/32" dev "$shim_if" >>"$log_file" 2>&1 || fail_with_log "Host shim route setup failed; inspect log: $log_file"
route_added=1
ip -o addr show "$shim_if" >>"$log_file" 2>&1 || true

shim_ping=FAIL
if ping -c 1 -W 2 "$container_ip" >"${output_dir}/host-shim-ping-${name}-${stamp}.log" 2>&1; then
    shim_ping=OK
fi

lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
started=0
ip route del "${container_ip}/32" dev "$shim_if" >>"$log_file" 2>&1 || true
route_added=0
ip link set "$shim_if" down >>"$log_file" 2>&1 || true
ip link del "$shim_if" >>"$log_file" 2>&1 || true
shim_created=0

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    fail_with_log "Container still RUNNING after host shim probe; inspect log: $log_file"
fi
if ip link show "$shim_if" >/dev/null 2>&1; then
    fail_with_log "Shim interface still exists after cleanup: $shim_if"
fi

printf '%s\n' '# LXC macvlan host shim probe summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'parent_if=%s\n' "$parent_if"
printf 'shim_if=%s\n' "$shim_if"
printf 'host_cidr=%s\n' "$host_cidr"
printf 'container_ip=%s\n' "$container_ip"
printf 'log=%s\n' "$log_file"
printf '\n'
printf 'dhcp_status=%s\n' "$dhcp_status"
printf 'detected_ip=%s\n' "$detected_ip"
printf 'gateway=%s\n' "$gateway"
printf 'shim_ping=%s\n' "$shim_ping"
printf 'cleanup=OK\n'
printf '\n'
printf '%s\n' 'Result: MACVLAN HOST SHIM PROBE COMPLETE. Container was stopped and shim was removed.'
