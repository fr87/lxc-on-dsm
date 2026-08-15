#!/bin/sh
# Generate a manual plan for a host-side macvlan shim. Does not change networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--parent-if IFACE] [--shim-if IFACE] [--host-cidr CIDR] [--container-ip IP] [--output DIRECTORY]"
}

parent_if=eth0
shim_if=lxcshim0
host_cidr=
container_ip=
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --parent-if) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; parent_if=$2; shift 2 ;;
        --shim-if) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; shim_if=$2; shift 2 ;;
        --host-cidr) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; host_cidr=$2; shift 2 ;;
        --container-ip) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; container_ip=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface: %s\n' "$parent_if" >&2; exit 2 ;; esac
case "$shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid shim interface: %s\n' "$shim_if" >&2; exit 2 ;; esac
case "$host_cidr" in *[!A-Za-z0-9_./:-]*) printf 'Invalid host CIDR: %s\n' "$host_cidr" >&2; exit 2 ;; esac
case "$container_ip" in *[!A-Za-z0-9_.:-]*) printf 'Invalid container IP: %s\n' "$container_ip" >&2; exit 2 ;; esac
if [ ${#parent_if} -gt 15 ]; then
    printf 'Parent interface name is too long for Linux interfaces: %s\n' "$parent_if" >&2
    exit 2
fi
if [ ${#shim_if} -gt 15 ]; then
    printf 'Shim interface name is too long for Linux interfaces: %s\n' "$shim_if" >&2
    exit 2
fi

host_cidr_display=${host_cidr:-'<HOST_SHIM_CIDR>'}
container_ip_display=${container_ip:-'<CONTAINER_IP>'}

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
plan_file="${output_dir}/macvlan-host-shim-plan-${stamp}.md"

{
    printf '%s\n' '# Macvlan host reachability shim plan'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'parent_if=%s\n' "$parent_if"
    printf 'shim_if=%s\n' "$shim_if"
    printf 'host_cidr=%s\n' "$host_cidr_display"
    printf 'container_ip=%s\n' "$container_ip_display"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- creates a temporary host-side macvlan interface'
    printf '%s\n' '- does not bridge or reconfigure the parent interface'
    printf '%s\n' '- does not change the DSM host address on the parent interface'
    printf '%s\n' '- adds only a narrow host route to the selected container IP'
    printf '%s\n' '- removes the temporary interface and route during cleanup'
    printf '\n'
    printf '%s\n' '## Required manual choices'
    printf '\n'
    printf '%s\n' '- Choose an unused LAN IP/CIDR for the host-side shim.'
    printf '%s\n' '- Prefer a DHCP reservation or an address outside the DHCP pool.'
    printf '%s\n' '- Do not reuse the container DHCP address as the shim address.'
    printf '%s\n' '- Re-run the macvlan DHCP probe if the container IP may have changed.'
    printf '\n'
    printf '%s\n' 'Example for the observed lab subnet only: if the container is `10.26.88.237/26`, choose a different free address such as `<FREE_LAN_IP>/26` for the host shim.'
    printf '\n'
    printf '%s\n' '## Pre-checks'
    printf '\n'
    printf '```sh\n'
    printf 'ip link show %s\n' "$shim_if"
    printf 'ip addr show %s\n' "$parent_if"
    printf 'ip route\n'
    printf '```\n'
    printf '\n'
    printf '%s\n' 'The shim interface should not already exist. Review the parent interface subnet before choosing the shim CIDR.'
    printf '\n'
    printf '%s\n' '## Manual shim commands'
    printf '\n'
    printf '%s\n' 'Run these only inside the Virtual DSM lab system, as root, after replacing placeholders with reviewed values:'
    printf '\n'
    printf '```sh\n'
    printf 'ip link add %s link %s type macvlan mode bridge\n' "$shim_if" "$parent_if"
    printf 'ip addr add %s dev %s\n' "$host_cidr_display" "$shim_if"
    printf 'ip link set %s up\n' "$shim_if"
    printf 'ip route add %s/32 dev %s\n' "$container_ip_display" "$shim_if"
    printf 'ping -c 1 -W 2 %s\n' "$container_ip_display"
    printf '```\n'
    printf '\n'
    printf '%s\n' '## Cleanup'
    printf '\n'
    printf '%s\n' 'Run cleanup even if the probe fails:'
    printf '\n'
    printf '```sh\n'
    printf 'ip route del %s/32 dev %s 2>/dev/null || true\n' "$container_ip_display" "$shim_if"
    printf 'ip link set %s down 2>/dev/null || true\n' "$shim_if"
    printf 'ip link del %s 2>/dev/null || true\n' "$shim_if"
    printf 'ip link show %s\n' "$shim_if"
    printf '```\n'
    printf '\n'
    printf '%s\n' 'The final `ip link show` should report that the shim interface no longer exists.'
    printf '\n'
    printf '%s\n' 'Result: MACVLAN HOST SHIM PLAN GENERATED. No networking was changed.'
} >"$plan_file"

cat "$plan_file"
