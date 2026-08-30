#!/bin/sh
# Read-only Phase 4 network prerequisite check. Does not create interfaces.
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
report_file="${output_dir}/network-prereqs-${stamp}.md"

have_command() {
    command -v "$1" >/dev/null 2>&1
}

module_evidence() {
    name=$1
    if [ -d "/sys/module/${name}" ]; then
        printf 'loaded'
    elif [ -r /proc/modules ] && grep -q "^${name}[[:space:]]" /proc/modules; then
        printf 'loaded'
    else
        printf 'unknown'
    fi
}

device_count() {
    if [ -r /proc/net/dev ]; then
        sed -n '3,$p' /proc/net/dev | wc -l | awk '{print $1}'
    else
        printf 'unknown'
    fi
}

{
    printf '%s\n' '# DSM LXC Phase 4 network prerequisite check'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'report=%s\n' "$report_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- read-only'
    printf '%s\n' '- no container start'
    printf '%s\n' '- no interface creation'
    printf '%s\n' '- no bridge, route, firewall or DSM network change'
    printf '\n'
    printf '%s\n' '## Host networking tools'
    printf '\n'
    if have_command ip; then
        printf '%s\n' '- OK: ip command is present'
    else
        printf '%s\n' '- WARN: ip command is missing'
    fi
    if have_command bridge; then
        printf '%s\n' '- OK: bridge command is present'
    else
        printf '%s\n' '- WARN: bridge command is missing'
    fi
    if have_command brctl; then
        printf '%s\n' '- OK: brctl command is present'
    else
        printf '%s\n' '- WARN: brctl command is missing'
    fi
    printf '\n'
    printf '%s\n' '## Kernel/module evidence'
    printf '\n'
    printf -- '- veth: %s\n' "$(module_evidence veth)"
    printf -- '- bridge: %s\n' "$(module_evidence bridge)"
    printf -- '- macvlan: %s\n' "$(module_evidence macvlan)"
    printf '\n'
    printf '%s\n' '## Existing interfaces'
    printf '\n'
    printf -- '- /proc/net/dev device count: %s\n' "$(device_count)"
    if [ -r /proc/net/dev ]; then
        sed -n '3,$s/:.*//p' /proc/net/dev | sed 's/^[[:space:]]*/- /'
    else
        printf '%s\n' '- WARN: /proc/net/dev is unavailable'
    fi
    printf '\n'
    printf '%s\n' '## Recommended next probes'
    printf '\n'
    printf '%s\n' '1. Keep the existing `alpine-lab` container networkless as a baseline.'
    printf '%s\n' '2. Create a separate throwaway network lab container config.'
    printf '%s\n' '3. First parse/test `lxc.net.0.type = empty`; do not attach DSM bridges.'
    printf '%s\n' '4. Probe `veth` only after host evidence looks acceptable.'
    printf '%s\n' '5. Treat bridge/macvlan as separate opt-in experiments.'
    printf '\n'
    printf '%s\n' 'Result: NETWORK PREFLIGHT COMPLETE. No networking was changed.'
} >"$report_file"

cat "$report_file"
