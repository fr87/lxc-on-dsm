#!/bin/sh
# Read-only DSM/LXC prerequisite collector. It only writes beneath --output.
set -eu

usage() { printf '%s\n' "Usage: $0 [--output DIRECTORY]"; }
output_dir="${PWD}/artifacts"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

timestamp=$(date -u '+%Y%m%dT%H%M%SZ')
run_dir="${output_dir}/dsm-lxc-analysis-${timestamp}"
raw_dir="${run_dir}/raw"
mkdir -p "$raw_dir"

capture() {
    name=$1; shift
    { printf '# command:'; printf ' %s' "$@"; printf '\n'; "$@" 2>&1 || printf '\n[exit status: %s]\n' "$?"; } >"${raw_dir}/${name}.txt"
}
capture_file() {
    name=$1; path=$2
    if [ -r "$path" ]; then capture "$name" cat "$path"; else printf '# unavailable: %s\n' "$path" >"${raw_dir}/${name}.txt"; fi
}

capture uname uname -a
capture_file synoinfo /etc.defaults/synoinfo.conf
capture_file os_release /etc/os-release
capture_file version /etc.defaults/VERSION
capture_file cpuinfo /proc/cpuinfo
capture_file cgroups /proc/cgroups
capture_file filesystems /proc/filesystems
capture_file mounts /proc/self/mountinfo
capture_file modules /proc/modules
capture_file unprivileged_userns /proc/sys/kernel/unprivileged_userns_clone
capture_file max_userns /proc/sys/user/max_user_namespaces
capture_file lsm /sys/kernel/security/lsm
capture namespaces ls -la /proc/self/ns
capture cgroup_tree ls -la /sys/fs/cgroup

config_path=""
for candidate in /proc/config.gz "/boot/config-$(uname -r)" /usr/lib/modules/"$(uname -r)"/build/.config; do
    if [ -r "$candidate" ]; then config_path=$candidate; break; fi
done
expanded_config="${run_dir}/kernel.config"
if [ "$config_path" = /proc/config.gz ] && command -v gzip >/dev/null 2>&1; then
    gzip -dc "$config_path" >"$expanded_config" 2>/dev/null || true
elif [ -n "$config_path" ]; then
    cp "$config_path" "$expanded_config"
fi

: >"${run_dir}/kernel-config.txt"
for key in CONFIG_NAMESPACES CONFIG_UTS_NS CONFIG_IPC_NS CONFIG_PID_NS CONFIG_NET_NS CONFIG_USER_NS \
    CONFIG_CGROUPS CONFIG_CGROUP_PIDS CONFIG_MEMCG CONFIG_CPUSETS CONFIG_CGROUP_DEVICE CONFIG_SECCOMP \
    CONFIG_SECCOMP_FILTER CONFIG_VETH CONFIG_BRIDGE CONFIG_MACVLAN CONFIG_VXLAN CONFIG_OVERLAY_FS \
    CONFIG_KEYS CONFIG_DEVPTS_MULTIPLE_INSTANCES CONFIG_SECURITY_APPARMOR; do
    if [ -r "$expanded_config" ]; then
        value=$(grep -E "^${key}(=| )" "$expanded_config" 2>/dev/null | tail -n 1 || true)
        [ -n "$value" ] || value="${key}=not-set"
    else
        value="${key}=unknown"
    fi
    printf '%s\n' "$value" >>"${run_dir}/kernel-config.txt"
done

{
    printf 'generated_utc=%s\n' "$timestamp"
    printf 'kernel=%s\n' "$(uname -r)"
    printf 'architecture=%s\n' "$(uname -m)"
    printf 'effective_uid=%s\n' "$(id -u)"
    printf 'kernel_config_source=%s\n' "${config_path:-unavailable}"
    for tool in lxc-start lxc-checkconfig newuidmap newgidmap unshare nsenter ip bridge nft iptables tar xz gzip; do
        if command -v "$tool" >/dev/null 2>&1; then state=present; else state=missing; fi
        printf 'tool_%s=%s\n' "$tool" "$state"
    done
} >"${run_dir}/summary.env"

cat >"${run_dir}/README.txt" <<'EOF'
Read-only prerequisite report. Review for hostnames, serial numbers, volume names,
and other identifiers before publishing. raw/ contains supporting evidence.
EOF
rm -f "$expanded_config"
archive="${run_dir}.tar.gz"
if command -v tar >/dev/null 2>&1; then
    tar -czf "$archive" -C "$output_dir" "$(basename "$run_dir")"
    printf 'Analysis complete: %s\n' "$archive"
else
    printf 'Analysis complete: %s (tar unavailable)\n' "$run_dir"
fi
