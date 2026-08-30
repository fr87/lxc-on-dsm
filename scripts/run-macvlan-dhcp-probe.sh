#!/bin/sh
# Probe real LAN connectivity using macvlan + DHCP inside the container.
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
config_file="${container_dir}/config"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
grep -q '^lxc\.net\.0\.type = macvlan$' "$config_file" || {
    printf 'Container is not configured for the macvlan DHCP gate: %s\n' "$config_file" >&2
    exit 1
}
parent_if=$(sed -n 's/^lxc\.net\.0\.link = //p' "$config_file" | sed -n '1p')
[ -n "$parent_if" ] || { printf 'Missing lxc.net.0.link parent interface in config: %s\n' "$config_file" >&2; exit 1; }
command -v ip >/dev/null 2>&1 || { printf 'Missing host ip command\n' >&2; exit 1; }
ip link show "$parent_if" >/dev/null 2>&1 || {
    printf 'Parent interface does not exist, refusing to start container: %s\n' "$parent_if" >&2
    exit 1
}

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-macvlan-dhcp-${name}-${stamp}.log"

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

write_probe_commands() {
    printf '%s\n' 'echo MACVLAN_DHCP_PROBE_BEGIN'
    printf '%s\n' 'printf "hostname="; hostname'
    printf '%s\n' 'printf "kernel="; uname -r'
    printf '%s\n' 'printf "tools_ip="; command -v ip >/dev/null 2>&1 && echo yes || echo no'
    printf '%s\n' 'printf "tools_udhcpc="; command -v udhcpc >/dev/null 2>&1 && echo yes || echo no'
    printf '%s\n' 'printf "tools_ping="; command -v ping >/dev/null 2>&1 && echo yes || echo no'
    printf '%s\n' 'printf "link_before_count="; ip -o link show 2>/dev/null | wc -l'
    printf '%s\n' 'printf "addr_before="; ip -4 -o addr show dev eth0 2>/dev/null | sed "s/[[:space:]][[:space:]]*/ /g" || true'
    printf '%s\n' 'dhcp_status=SKIPPED'
    printf '%s\n' 'if command -v udhcpc >/dev/null 2>&1; then udhcpc -i eth0 -n -q -t 3 -T 3 >/tmp/udhcpc.log 2>&1 && dhcp_status=OK || dhcp_status=FAIL; fi'
    printf '%s\n' 'printf "dhcp_status=%s\n" "$dhcp_status"'
    printf '%s\n' 'printf "udhcpc_log="; tr "\n" "|" </tmp/udhcpc.log 2>/dev/null || true; echo'
    printf '%s\n' 'printf "addr_after="; ip -4 -o addr show dev eth0 2>/dev/null | sed "s/[[:space:]][[:space:]]*/ /g" || true'
    printf '%s\n' 'printf "routes_after="; ip route 2>/dev/null | tr "\n" "|" || true; echo'
    printf '%s\n' 'gateway=$(ip route 2>/dev/null | awk "/^default / {print \$3; exit}")'
    printf '%s\n' 'if [ -n "$gateway" ]; then ping -c 1 -W 2 "$gateway" >/tmp/ping-gateway.log 2>&1 && gateway_ping=OK || gateway_ping=FAIL; else gateway_ping=SKIPPED; fi'
    printf '%s\n' 'printf "gateway=%s\n" "${gateway:-}"'
    printf '%s\n' 'printf "gateway_ping=%s\n" "$gateway_ping"'
    printf '%s\n' 'printf "ping_gateway_log="; tr "\n" "|" </tmp/ping-gateway.log 2>/dev/null || true; echo'
    printf '%s\n' 'if ping -c 1 -W 2 1.1.1.1 >/tmp/ping-internet.log 2>&1; then internet_ping=OK; else internet_ping=FAIL; fi'
    printf '%s\n' 'printf "internet_ping=%s\n" "$internet_ping"'
    printf '%s\n' 'printf "ping_internet_log="; tr "\n" "|" </tmp/ping-internet.log 2>/dev/null || true; echo'
    printf '%s\n' 'echo MACVLAN_DHCP_PROBE_END'
    printf '%s\n' 'exit'
}

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi

printf '%s\n' '# LXC macvlan DHCP probe'
printf '\n'
printf 'container=%s\n' "$name"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'parent_if=%s\n' "$parent_if"
printf 'log=%s\n' "$log_file"
printf '\n'

{
    printf '%s\n' '# LXC macvlan DHCP probe'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'config=%s\n' "$config_file"
    printf 'parent_if=%s\n' "$parent_if"
    printf '\n## config network lines\n'
    grep -E '^lxc\.net\.|^lxc\.start\.auto' "$config_file" || true
    printf '\n## host parent before\n'
    ip -o link show "$parent_if" || true
    printf '\n## foreground DHCP evidence\n'
} >"$log_file"

if ! write_probe_commands | lxc-start -F -P "$state_dir" -n "$name" >>"$log_file" 2>&1; then
    fail_with_log "Macvlan DHCP foreground probe failed; inspect log: $log_file"
fi

if ! grep -q 'MACVLAN_DHCP_PROBE_BEGIN' "$log_file" || ! grep -q 'MACVLAN_DHCP_PROBE_END' "$log_file"; then
    fail_with_log "Macvlan DHCP probe markers missing; inspect log: $log_file"
fi

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container still RUNNING after macvlan DHCP probe; stopping: %s\n' "$name" >&2
    lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
fi

printf '%s\n' '# LXC macvlan DHCP probe summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'parent_if=%s\n' "$parent_if"
printf 'log=%s\n' "$log_file"
printf '\n'
grep -E 'MACVLAN_DHCP_PROBE_|^hostname=|^kernel=|^tools_|^link_before_count=|^addr_before=|^dhcp_status=|^addr_after=|^routes_after=|^gateway=|^gateway_ping=|^internet_ping=' "$log_file"
printf '\nResult: MACVLAN DHCP PROBE COMPLETE. Parent interface was not bridged or reconfigured by this script.\n'
