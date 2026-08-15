#!/bin/sh
# Start the profiled macvlan lab container and optional host shim.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--profile FILE] [--output DIRECTORY]"
}

profile_file=config/lab-macvlan.env
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -r "$profile_file" ] || { printf 'Missing profile: %s\n' "$profile_file" >&2; exit 1; }
. "$profile_file"

prefix=${LXC_LAB_PREFIX:-}
state_dir=${LXC_LAB_STATE_DIR:-}
name=${LXC_LAB_CONTAINER:-}
parent_if=${LXC_LAB_PARENT_IF:-}
shim_if=${LXC_LAB_SHIM_IF:-}
host_cidr=${LXC_LAB_HOST_SHIM_CIDR:-}

[ -n "$prefix" ] || { printf 'Profile missing LXC_LAB_PREFIX\n' >&2; exit 1; }
[ -n "$state_dir" ] || { printf 'Profile missing LXC_LAB_STATE_DIR\n' >&2; exit 1; }
[ -n "$name" ] || { printf 'Profile missing LXC_LAB_CONTAINER\n' >&2; exit 1; }
[ -n "$parent_if" ] || { printf 'Profile missing LXC_LAB_PARENT_IF\n' >&2; exit 1; }
[ -n "$shim_if" ] || { printf 'Profile missing LXC_LAB_SHIM_IF\n' >&2; exit 1; }
case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 1 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 1 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 1 ;; esac
case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface: %s\n' "$parent_if" >&2; exit 1 ;; esac
case "$shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid shim interface: %s\n' "$shim_if" >&2; exit 1 ;; esac
case "$host_cidr" in *[!A-Za-z0-9_./:-]*) printf 'Invalid host shim CIDR: %s\n' "$host_cidr" >&2; exit 1 ;; esac

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"
runtime_state="${container_dir}/lifecycle-state.env"
evidence_file="${rootfs_dir}/tmp/dsm-lxc-macvlan-lifecycle.env"

[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }
grep -q '^lxc\.net\.0\.type = macvlan$' "$config_file" || { printf 'Container is not configured for macvlan: %s\n' "$config_file" >&2; exit 1; }
grep -Fqx "lxc.net.0.link = ${parent_if}" "$config_file" || { printf 'Container parent interface does not match profile: %s\n' "$parent_if" >&2; exit 1; }
command -v ip >/dev/null 2>&1 || { printf 'Missing host ip command\n' >&2; exit 1; }
command -v lxc-start >/dev/null 2>&1 || { printf 'Missing lxc-start command\n' >&2; exit 1; }
command -v lxc-info >/dev/null 2>&1 || { printf 'Missing lxc-info command\n' >&2; exit 1; }
ip link show "$parent_if" >/dev/null 2>&1 || { printf 'Parent interface missing: %s\n' "$parent_if" >&2; exit 1; }
if ip link show "$shim_if" >/dev/null 2>&1; then
    printf 'Shim interface already exists, refusing to take over: %s\n' "$shim_if" >&2
    exit 1
fi
if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to start it again: %s\n' "$name" >&2
    exit 1
fi

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-lifecycle-start-${name}-${stamp}.log"
shim_created=0
route_added=0
started=0
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

cleanup_on_failure() {
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
trap cleanup_on_failure EXIT HUP INT TERM

if [ -e "$evidence_file" ]; then
    mv "$evidence_file" "${evidence_file}.previous"
fi

{
    printf '%s\n' '# LXC macvlan lifecycle start'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'profile=%s\n' "$profile_file"
    printf 'container=%s\n' "$name"
    printf 'parent_if=%s\n' "$parent_if"
    printf 'shim_if=%s\n' "$shim_if"
    printf 'host_cidr=%s\n' "$host_cidr"
    printf '\n## config network lines\n'
    grep -E '^lxc\.net\.|^lxc\.start\.auto' "$config_file" || true
    printf '\n## detached container start\n'
} >"$log_file"

if ! lxc-start -d -P "$state_dir" -n "$name" -- /bin/sh -c '
    evidence=/tmp/dsm-lxc-macvlan-lifecycle.env
    dhcp_status=SKIPPED
    if command -v udhcpc >/dev/null 2>&1; then
        udhcpc -i eth0 -n -q -t 3 -T 3 >/tmp/udhcpc-lifecycle.log 2>&1 && dhcp_status=OK || dhcp_status=FAIL
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
        printf "udhcpc_log=%s\n" "$(tr "\n" "|" </tmp/udhcpc-lifecycle.log 2>/dev/null || true)"
    } >"$evidence"
    trap "exit 0" TERM INT
    while :; do sleep 3600; done
' >>"$log_file" 2>&1; then
    fail_with_log "Detached macvlan lifecycle start failed; inspect log: $log_file"
fi
started=1

i=0
while [ "$i" -lt 15 ]; do
    [ -r "$evidence_file" ] && break
    i=$((i + 1))
    sleep 1
done

[ -r "$evidence_file" ] || fail_with_log "Container did not write lifecycle evidence: $evidence_file"
cat "$evidence_file" >>"$log_file"
dhcp_status=$(sed -n 's/^dhcp_status=//p' "$evidence_file" | sed -n '1p')
container_ip=$(sed -n 's/^ip_plain=//p' "$evidence_file" | sed -n '1p')
gateway=$(sed -n 's/^gateway=//p' "$evidence_file" | sed -n '1p')
[ -n "$container_ip" ] || fail_with_log "Container IP is empty after lifecycle start"

if [ -n "$host_cidr" ]; then
    host_ip_plain=${host_cidr%%/*}
    if [ "$host_ip_plain" = "$container_ip" ]; then
        fail_with_log "Host shim IP equals container IP; choose a different free LAN address: $host_cidr"
    fi
    printf '\n## host shim setup\n' >>"$log_file"
    ip link add "$shim_if" link "$parent_if" type macvlan mode bridge >>"$log_file" 2>&1 || fail_with_log "Host shim creation failed; inspect log: $log_file"
    shim_created=1
    ip addr add "$host_cidr" dev "$shim_if" >>"$log_file" 2>&1 || fail_with_log "Host shim address assignment failed; inspect log: $log_file"
    ip link set "$shim_if" up >>"$log_file" 2>&1 || fail_with_log "Host shim activation failed; inspect log: $log_file"
    ip route add "${container_ip}/32" dev "$shim_if" >>"$log_file" 2>&1 || fail_with_log "Host shim route setup failed; inspect log: $log_file"
    route_added=1
    ip -o addr show "$shim_if" >>"$log_file" 2>&1 || true
fi

{
    printf '%s\n' '# LXC macvlan lifecycle runtime state'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'profile=%s\n' "$profile_file"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'parent_if=%s\n' "$parent_if"
    printf 'shim_if=%s\n' "$shim_if"
    printf 'host_cidr=%s\n' "$host_cidr"
    printf 'container_ip=%s\n' "$container_ip"
    printf 'gateway=%s\n' "$gateway"
    printf 'dhcp_status=%s\n' "$dhcp_status"
    printf 'shim_created=%s\n' "$shim_created"
    printf 'route_added=%s\n' "$route_added"
    printf 'log=%s\n' "$log_file"
} >"$runtime_state"

trap - EXIT HUP INT TERM

printf '%s\n' '# LXC macvlan lifecycle start summary'
printf '\n'
printf 'profile=%s\n' "$profile_file"
printf 'container=%s\n' "$name"
printf 'parent_if=%s\n' "$parent_if"
printf 'shim_if=%s\n' "$shim_if"
printf 'host_cidr=%s\n' "$host_cidr"
printf 'container_ip=%s\n' "$container_ip"
printf 'gateway=%s\n' "$gateway"
printf 'dhcp_status=%s\n' "$dhcp_status"
printf 'shim_created=%s\n' "$shim_created"
printf 'route_added=%s\n' "$route_added"
printf 'runtime_state=%s\n' "$runtime_state"
printf 'log=%s\n' "$log_file"
printf '\n'
printf '%s\n' 'Result: MACVLAN LIFECYCLE STARTED. Stop with scripts/stop-macvlan-profile.sh.'
