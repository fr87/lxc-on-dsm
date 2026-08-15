#!/bin/sh
# Read-only bridge prerequisite check. Does not create or modify bridges.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--output DIRECTORY]"
}

output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
report_file="${output_dir}/bridge-prereqs-${stamp}.md"

have_command() {
    command -v "$1" >/dev/null 2>&1
}

list_sysfs_bridges() {
    found=0
    for bridge_dir in /sys/class/net/*/bridge; do
        [ -d "$bridge_dir" ] || continue
        found=1
        bridge_name=${bridge_dir%/bridge}
        bridge_name=${bridge_name##*/}
        printf '%s\n' "$bridge_name"
    done
    [ "$found" -eq 1 ] || true
}

bridge_ports() {
    bridge_name=$1
    ports_dir="/sys/class/net/${bridge_name}/brif"
    if [ -d "$ports_dir" ]; then
        for port in "$ports_dir"/*; do
            [ -e "$port" ] || continue
            printf '%s ' "${port##*/}"
        done
        printf '\n'
    fi
}

{
    printf '%s\n' '# DSM LXC Phase 4 bridge prerequisite check'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'report=%s\n' "$report_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- read-only'
    printf '%s\n' '- no container start'
    printf '%s\n' '- no interface creation'
    printf '%s\n' '- no bridge membership changes'
    printf '%s\n' '- no IP, route, firewall or DSM network changes'
    printf '\n'
    printf '%s\n' '## Tools'
    printf '\n'
    if have_command ip; then
        printf '%s\n' '- OK: ip command is present'
    else
        printf '%s\n' '- WARN: ip command is missing'
    fi
    if have_command brctl; then
        printf '%s\n' '- OK: brctl command is present'
    else
        printf '%s\n' '- WARN: brctl command is missing'
    fi
    if have_command bridge; then
        printf '%s\n' '- OK: bridge command is present'
    else
        printf '%s\n' '- WARN: bridge command is missing'
    fi
    printf '\n'
    printf '%s\n' '## Existing interfaces'
    printf '\n'
    if have_command ip; then
        ip -o link show | sed 's/^/- /'
    elif [ -r /proc/net/dev ]; then
        sed -n '3,$s/:.*//p' /proc/net/dev | sed 's/^[[:space:]]*/- /'
    else
        printf '%s\n' '- WARN: no interface listing available'
    fi
    printf '\n'
    printf '%s\n' '## brctl show'
    printf '\n'
    if have_command brctl; then
        printf '```text\n'
        brctl show 2>&1 || true
        printf '```\n'
    else
        printf '%s\n' '- skipped: brctl missing'
    fi
    printf '\n'
    printf '%s\n' '## sysfs bridges'
    printf '\n'
    bridges=$(list_sysfs_bridges)
    if [ -n "$bridges" ]; then
        printf '%s\n' "$bridges" | while IFS= read -r bridge_name; do
            [ -n "$bridge_name" ] || continue
            ports=$(bridge_ports "$bridge_name")
            if [ -n "$ports" ]; then
                printf -- '- %s ports: %s\n' "$bridge_name" "$ports"
            else
                printf -- '- %s ports: none observed\n' "$bridge_name"
            fi
        done
    else
        printf '%s\n' '- none observed'
    fi
    printf '\n'
    printf '%s\n' '## Gate decision'
    printf '\n'
    printf '%s\n' '- Do not attach LXC veth to a bridge until this report has been reviewed.'
    printf '%s\n' '- Prefer a dedicated lab bridge over DSM production bridges for the first bridge experiment.'
    printf '%s\n' '- If only production DSM interfaces exist, keep the next test detached from LAN.'
    printf '\n'
    printf '%s\n' 'Result: BRIDGE PREFLIGHT COMPLETE. No networking was changed.'
} >"$report_file"

cat "$report_file"
