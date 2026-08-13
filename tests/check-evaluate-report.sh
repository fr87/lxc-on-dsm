#!/bin/sh
set -eu

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
report="$tmp_dir/report"
mkdir -p "$report/raw"

cat >"$report/summary.env" <<'EOF'
generated_utc=20260813T000000Z
kernel=4.4.302+
architecture=x86_64
effective_uid=0
kernel_config_source=/proc/config.gz
tool_lxc_start=missing
tool_lxc_checkconfig=missing
tool_newuidmap=missing
tool_newgidmap=missing
tool_unshare=present
tool_nsenter=present
tool_ip=present
tool_bridge=present
tool_tar=present
tool_xz=present
tool_gzip=present
EOF

cat >"$report/kernel-config.txt" <<'EOF'
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_PIDS=y
CONFIG_SECCOMP=y
CONFIG_MEMCG=y
CONFIG_USER_NS=y
CONFIG_SECCOMP_FILTER=y
CONFIG_CGROUP_DEVICE=y
CONFIG_DEVPTS_MULTIPLE_INSTANCES=y
CONFIG_KEYS=y
CONFIG_OVERLAY_FS=y
CONFIG_VETH=m
CONFIG_BRIDGE=m
CONFIG_MACVLAN=m
EOF

cat >"$report/raw/cgroups.txt" <<'EOF'
#subsys_name	hierarchy	num_cgroups	enabled
pids	1	1	1
devices	2	1	1
memory	3	1	1
EOF

output=$(sh scripts/evaluate-report.sh "$report")
printf '%s\n' "$output" | grep -q 'PASS WITH CAUTION'
printf '%s\n' "$output" | grep -q 'TODO: lxc-start is missing'
printf '%s\n' "$output" | grep -q 'OK: Network namespaces'
