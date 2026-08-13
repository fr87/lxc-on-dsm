#!/bin/sh
# Evaluate a read-only DSM/LXC prerequisite report.
set -eu

usage() { printf '%s\n' "Usage: $0 REPORT_DIR [--output FILE]"; }

[ "$#" -ge 1 ] || { usage >&2; exit 2; }
case "$1" in
    -h|--help) usage; exit 0 ;;
esac
report_dir=$1
shift
output_file=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_file=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -f "$report_dir/summary.env" ] && [ -f "$report_dir/kernel-config.txt" ] || {
    printf 'Invalid report: %s\n' "$report_dir" >&2
    exit 2
}

if [ -n "$output_file" ]; then
    : >"$output_file"
fi

emit() {
    if [ -n "$output_file" ]; then
        printf '%s\n' "$*" | tee -a "$output_file"
    else
        printf '%s\n' "$*"
    fi
}

summary_value() {
    key=$1
    line=$(grep -E "^${key}=" "$report_dir/summary.env" 2>/dev/null | tail -n 1 || true)
    [ -n "$line" ] || { printf 'unknown'; return; }
    printf '%s' "${line#*=}"
}

config_state() {
    key=$1
    line=$(grep -E "^${key}=|^# ${key} is not set$" "$report_dir/kernel-config.txt" 2>/dev/null | tail -n 1 || true)
    case "$line" in
        "$key=y") printf 'enabled' ;;
        "$key=m") printf 'module' ;;
        "$key=unknown") printf 'unknown' ;;
        "$key=not-set"|"# $key is not set") printf 'not-set' ;;
        "$key="*) printf '%s' "${line#*=}" ;;
        *) printf 'unknown' ;;
    esac
}

cgroup_enabled() {
    name=$1
    file="$report_dir/raw/cgroups.txt"
    [ -r "$file" ] || { printf 'unknown'; return; }
    line=$(awk -v name="$name" '$1 == name { print $0; found=1 } END { if (!found) exit 1 }' "$file" 2>/dev/null || true)
    [ -n "$line" ] || { printf 'unknown'; return; }
    enabled=$(printf '%s\n' "$line" | awk '{ print $4 }')
    if [ "$enabled" = 1 ]; then printf 'enabled'; else printf 'disabled'; fi
}

tool_state() {
    tool=$1
    safe_tool_name=$(printf '%s' "$tool" | sed 's/[-.]/_/g')
    state=$(summary_value "tool_${safe_tool_name}")
    if [ "$state" != unknown ]; then
        printf '%s' "$state"
        return
    fi
    summary_value "tool_${tool}"
}

blocked=0
warnings=0

require_config() {
    key=$1
    label=$2
    state=$(config_state "$key")
    case "$state" in
        enabled|module) emit "- OK: $label ($key=$state)" ;;
        unknown) emit "- WARN: $label ($key unknown)"; warnings=$((warnings + 1)) ;;
        *) emit "- BLOCKER: $label ($key=$state)"; blocked=$((blocked + 1)) ;;
    esac
}

recommend_config() {
    key=$1
    label=$2
    state=$(config_state "$key")
    case "$state" in
        enabled|module) emit "- OK: $label ($key=$state)" ;;
        *) emit "- WARN: $label ($key=$state)"; warnings=$((warnings + 1)) ;;
    esac
}

require_cgroup() {
    name=$1
    label=$2
    state=$(cgroup_enabled "$name")
    case "$state" in
        enabled) emit "- OK: $label cgroup is enabled" ;;
        unknown) emit "- WARN: $label cgroup state unknown"; warnings=$((warnings + 1)) ;;
        *) emit "- BLOCKER: $label cgroup is $state"; blocked=$((blocked + 1)) ;;
    esac
}

emit "# DSM LXC preflight"
emit ""
emit "- report: $report_dir"
emit "- generated_utc: $(summary_value generated_utc)"
emit "- kernel: $(summary_value kernel)"
emit "- architecture: $(summary_value architecture)"
emit "- effective_uid: $(summary_value effective_uid)"
emit "- kernel_config_source: $(summary_value kernel_config_source)"
emit ""
emit "## Required kernel primitives"
require_config CONFIG_NAMESPACES "Namespace support"
require_config CONFIG_UTS_NS "UTS namespaces"
require_config CONFIG_IPC_NS "IPC namespaces"
require_config CONFIG_PID_NS "PID namespaces"
require_config CONFIG_NET_NS "Network namespaces"
require_config CONFIG_CGROUPS "Cgroups"
require_config CONFIG_CGROUP_PIDS "PIDs cgroup"
require_config CONFIG_SECCOMP "Seccomp"
emit ""
emit "## Runtime cgroups"
require_cgroup pids "PIDs"
require_cgroup devices "Devices"
recommend_config CONFIG_MEMCG "Memory cgroup kernel support"
require_cgroup memory "Memory"
emit ""
emit "## Strongly recommended features"
recommend_config CONFIG_USER_NS "User namespaces"
recommend_config CONFIG_SECCOMP_FILTER "Seccomp filters"
recommend_config CONFIG_CGROUP_DEVICE "Device cgroup kernel support"
recommend_config CONFIG_DEVPTS_MULTIPLE_INSTANCES "Multiple devpts instances"
recommend_config CONFIG_KEYS "Kernel keyrings"
emit ""
emit "## Storage and networking"
recommend_config CONFIG_OVERLAY_FS "OverlayFS"
recommend_config CONFIG_VETH "veth networking"
recommend_config CONFIG_BRIDGE "Linux bridge"
recommend_config CONFIG_MACVLAN "macvlan networking"
emit ""
emit "## Userspace tools"
for tool in lxc-start lxc-checkconfig newuidmap newgidmap unshare nsenter ip bridge tar xz gzip; do
    state=$(tool_state "$tool")
    case "$tool:$state" in
        lxc-start:present|lxc-checkconfig:present) emit "- OK: $tool is present" ;;
        lxc-start:*|lxc-checkconfig:*) emit "- TODO: $tool is $state; expected before container start" ;;
        *:present) emit "- OK: $tool is present" ;;
        *) emit "- WARN: $tool is $state"; warnings=$((warnings + 1)) ;;
    esac
done
emit ""
if [ "$blocked" -gt 0 ]; then
    emit "## Result"
    emit "BLOCKED: $blocked blocker(s), $warnings warning(s). Do not attempt LXC startup yet."
    exit 1
fi
emit "## Result"
emit "PASS WITH CAUTION: no hard blocker detected, $warnings warning(s). Proceed to userspace/toolchain experiments in Virtual DSM."
