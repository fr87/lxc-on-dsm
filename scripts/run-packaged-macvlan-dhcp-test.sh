#!/bin/sh
# Probe real LAN connectivity for a package-created macvlan container.
# Dry-run by default. Pass --run to start the container once, request DHCP,
# collect evidence and stop again.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --name NAME [--package NAME] [--prefix DIRECTORY] [--state-dir DIRECTORY] [--output DIRECTORY] [--run]"
}

package_name=lxc-on-dsm
prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
output_dir=
name=
run=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --run) run=1; shift ;;
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

if [ "$run" -eq 1 ]; then
    [ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged macvlan DHCP test requires uid=0.' >&2; exit 1; }
fi

PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
grep -q '^lxc\.net\.0\.type = macvlan$' "$config_file" || {
    printf '%s\n' 'Refusing DHCP test because container is not configured with lxc.net.0.type = macvlan.' >&2
    exit 1
}
grep -q '^lxc\.start\.auto = 0$' "$config_file" || {
    printf '%s\n' 'Refusing DHCP test because container is not configured with lxc.start.auto = 0.' >&2
    exit 1
}
parent_if=$(sed -n 's/^lxc\.net\.0\.link = //p' "$config_file" | sed -n '1p')
[ -n "$parent_if" ] || { printf 'Missing lxc.net.0.link parent interface in config: %s\n' "$config_file" >&2; exit 1; }
case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface in config: %s\n' "$parent_if" >&2; exit 1 ;; esac

command -v ip >/dev/null 2>&1 || { printf 'Missing host ip command\n' >&2; exit 1; }
ip link show "$parent_if" >/dev/null 2>&1 || {
    printf 'Parent interface does not exist, refusing to start container: %s\n' "$parent_if" >&2
    exit 1
}

printf '%s\n' '# Packaged LXC macvlan DHCP test'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'run=%s\n' "$run"
printf 'container=%s\n' "$name"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'parent_if=%s\n' "$parent_if"
printf 'output=%s\n' "$output_dir"
printf '\n'

if [ "$run" -ne 1 ]; then
    printf '%s\n' 'Result: PACKAGED MACVLAN DHCP TEST DRY RUN COMPLETE. No container was started and no networking was changed.'
    exit 0
fi

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-packaged-macvlan-dhcp-${name}-${stamp}.log"

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
    printf '%s\n' 'echo DSM_LXC_PACKAGED_MACVLAN_DHCP_BEGIN'
    printf '%s\n' 'printf "hostname="; hostname'
    printf '%s\n' 'printf "kernel="; uname -r'
    printf '%s\n' 'printf "tools_ip="; command -v ip >/dev/null 2>&1 && echo yes || echo no'
    printf '%s\n' 'printf "tools_udhcpc="; command -v udhcpc >/dev/null 2>&1 && echo yes || echo no'
    printf '%s\n' 'printf "tools_ping="; command -v ping >/dev/null 2>&1 && echo yes || echo no'
    printf '%s\n' 'printf "addr_before="; ip -4 -o addr show dev eth0 2>/dev/null | sed "s/[[:space:]][[:space:]]*/ /g" || true'
    printf '%s\n' 'dhcp_status=SKIPPED'
    printf '%s\n' 'if command -v udhcpc >/dev/null 2>&1; then udhcpc -i eth0 -n -q -t 3 -T 3 >/tmp/udhcpc-packaged.log 2>&1 && dhcp_status=OK || dhcp_status=FAIL; fi'
    printf '%s\n' 'printf "dhcp_status=%s\n" "$dhcp_status"'
    printf '%s\n' 'printf "udhcpc_log="; tr "\n" "|" </tmp/udhcpc-packaged.log 2>/dev/null || true; echo'
    printf '%s\n' 'printf "addr_after="; ip -4 -o addr show dev eth0 2>/dev/null | sed "s/[[:space:]][[:space:]]*/ /g" || true'
    printf '%s\n' 'printf "routes_after="; ip route 2>/dev/null | tr "\n" "|" || true; echo'
    printf '%s\n' 'gateway=$(ip route 2>/dev/null | awk "/^default / {print \$3; exit}")'
    printf '%s\n' 'if [ -n "$gateway" ]; then ping -c 1 -W 2 "$gateway" >/tmp/ping-gateway-packaged.log 2>&1 && gateway_ping=OK || gateway_ping=FAIL; else gateway_ping=SKIPPED; fi'
    printf '%s\n' 'printf "gateway=%s\n" "${gateway:-}"'
    printf '%s\n' 'printf "gateway_ping=%s\n" "$gateway_ping"'
    printf '%s\n' 'if ping -c 1 -W 2 1.1.1.1 >/tmp/ping-internet-packaged.log 2>&1; then internet_ping=OK; else internet_ping=FAIL; fi'
    printf '%s\n' 'printf "internet_ping=%s\n" "$internet_ping"'
    printf '%s\n' 'echo DSM_LXC_PACKAGED_MACVLAN_DHCP_END'
    printf '%s\n' 'exit'
}

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi

{
    printf '%s\n' '# Packaged LXC macvlan DHCP test'
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
    fail_with_log "Packaged macvlan DHCP test failed; inspect log: $log_file"
fi

if ! grep -q 'DSM_LXC_PACKAGED_MACVLAN_DHCP_BEGIN' "$log_file" || ! grep -q 'DSM_LXC_PACKAGED_MACVLAN_DHCP_END' "$log_file"; then
    fail_with_log "Packaged macvlan DHCP markers missing; inspect log: $log_file"
fi

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container still RUNNING after DHCP command; stopping: %s\n' "$name" >&2
    lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
fi

printf '%s\n' '# Packaged LXC macvlan DHCP test summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'parent_if=%s\n' "$parent_if"
printf 'log=%s\n' "$log_file"
printf '\n'
grep -E 'DSM_LXC_PACKAGED_MACVLAN_DHCP_|^hostname=|^kernel=|^tools_|^addr_before=|^dhcp_status=|^addr_after=|^routes_after=|^gateway=|^gateway_ping=|^internet_ping=' "$log_file"
printf '\nResult: PACKAGED MACVLAN DHCP TEST COMPLETE. Parent interface was not bridged or reconfigured by this script.\n'
