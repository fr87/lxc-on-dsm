#!/bin/sh
# Generate a manual plan for an isolated lab bridge. Does not change networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--bridge NAME] [--container NAME] [--host-veth NAME] [--output DIRECTORY]"
}

bridge_name=lxcbrlab0
container_name=alpine-bridgelab
host_veth=lxcbrveth0
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --bridge) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; bridge_name=$2; shift 2 ;;
        --container) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; container_name=$2; shift 2 ;;
        --host-veth) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; host_veth=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$bridge_name" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid bridge name: %s\n' "$bridge_name" >&2; exit 2 ;; esac
case "$container_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$container_name" >&2; exit 2 ;; esac
case "$host_veth" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid host veth name: %s\n' "$host_veth" >&2; exit 2 ;; esac
if [ ${#bridge_name} -gt 15 ]; then
    printf 'Bridge name is too long for Linux interfaces: %s\n' "$bridge_name" >&2
    exit 2
fi
if [ ${#host_veth} -gt 15 ]; then
    printf 'Host veth name is too long for Linux interfaces: %s\n' "$host_veth" >&2
    exit 2
fi

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
plan_file="${output_dir}/isolated-bridge-plan-${stamp}.md"

{
    printf '%s\n' '# Isolated LXC bridge probe plan'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'bridge=%s\n' "$bridge_name"
    printf 'container=%s\n' "$container_name"
    printf 'host_veth=%s\n' "$host_veth"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- creates a temporary host bridge'
    printf '%s\n' '- does not attach `eth0` or any DSM production interface'
    printf '%s\n' '- does not request DHCP'
    printf '%s\n' '- does not assign an IP address'
    printf '%s\n' '- does not change routes or firewall rules'
    printf '%s\n' '- removes the temporary bridge after the probe'
    printf '\n'
    printf '%s\n' '## Pre-checks'
    printf '\n'
    printf '```sh\n'
    printf 'ip link show %s\n' "$bridge_name"
    printf 'ip link show %s\n' "$host_veth"
    printf 'brctl show\n'
    printf '```\n'
    printf '\n'
    printf '%s\n' 'Both `ip link show` commands should report that the device does not exist.'
    printf '\n'
    printf '%s\n' '## Manual isolated bridge commands'
    printf '\n'
    printf '%s\n' 'Run these only inside the Virtual DSM lab system, as root, after reviewing the pre-checks:'
    printf '\n'
    printf '```sh\n'
    printf 'brctl addbr %s\n' "$bridge_name"
    printf 'ip link set %s up\n' "$bridge_name"
    printf 'brctl show\n'
    printf '\n'
    printf 'sh scripts/create-netlab-container.sh --prefix /volume1/@lxc/lab/opt --name %s --network-type veth --host-veth %s\n' "$container_name" "$host_veth"
    printf 'sed -i.bak "/^lxc.net.0.veth.pair = /a lxc.net.0.link = %s" /volume1/@lxc/lab/containers/%s/config\n' "$bridge_name" "$container_name"
    printf 'sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name %s\n' "$container_name"
    printf 'sh scripts/run-veth-network-probe.sh --prefix /volume1/@lxc/lab/opt --name %s\n' "$container_name"
    printf '\n'
    printf 'ip link show %s\n' "$bridge_name"
    printf 'brctl show %s\n' "$bridge_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' '## Cleanup'
    printf '\n'
    printf '%s\n' 'Run cleanup even if the probe fails:'
    printf '\n'
    printf '```sh\n'
    printf 'lxc-stop -P /volume1/@lxc/lab/containers -n %s 2>/dev/null || true\n' "$container_name"
    printf 'ip link set %s down\n' "$bridge_name"
    printf 'brctl delbr %s\n' "$bridge_name"
    printf 'ip link show %s\n' "$bridge_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' 'The final `ip link show` should report that the bridge no longer exists.'
    printf '\n'
    printf '%s\n' 'Result: ISOLATED BRIDGE PLAN GENERATED. No networking was changed.'
} >"$plan_file"

cat "$plan_file"
