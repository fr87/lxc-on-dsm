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
CONFIG_MOUNT_NS=y
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

unknown_report="$tmp_dir/unknown-report"
mkdir -p "$unknown_report/raw"
cp "$report/summary.env" "$unknown_report/summary.env"
cat >"$unknown_report/kernel-config.txt" <<'EOF'
CONFIG_NAMESPACES=unknown
CONFIG_UTS_NS=unknown
CONFIG_IPC_NS=unknown
CONFIG_PID_NS=unknown
CONFIG_NET_NS=unknown
CONFIG_MOUNT_NS=unknown
CONFIG_CGROUPS=unknown
CONFIG_CGROUP_PIDS=unknown
CONFIG_SECCOMP=unknown
CONFIG_MEMCG=unknown
CONFIG_USER_NS=unknown
CONFIG_SECCOMP_FILTER=unknown
CONFIG_CGROUP_DEVICE=unknown
CONFIG_DEVPTS_MULTIPLE_INSTANCES=unknown
CONFIG_KEYS=unknown
CONFIG_OVERLAY_FS=unknown
CONFIG_VETH=unknown
CONFIG_BRIDGE=unknown
CONFIG_MACVLAN=unknown
EOF
cat >"$unknown_report/raw/namespaces.txt" <<'EOF'
lrwxrwxrwx 1 root root 0 Aug 13 18:33 ipc -> ipc:[4026531839]
lrwxrwxrwx 1 root root 0 Aug 13 18:33 mnt -> mnt:[4026531840]
lrwxrwxrwx 1 root root 0 Aug 13 18:33 net -> net:[4026531992]
lrwxrwxrwx 1 root root 0 Aug 13 18:33 pid -> pid:[4026531836]
lrwxrwxrwx 1 root root 0 Aug 13 18:33 uts -> uts:[4026531838]
EOF
cat >"$unknown_report/raw/cgroups.txt" <<'EOF'
#subsys_name	hierarchy	num_cgroups	enabled
devices	2	1	1
memory	3	1	1
EOF

set +e
unknown_output=$(sh scripts/evaluate-report.sh "$unknown_report" 2>&1)
unknown_status=$?
set -e
[ "$unknown_status" -eq 3 ]
printf '%s\n' "$unknown_output" | grep -q 'INCONCLUSIVE'
printf '%s\n' "$unknown_output" | grep -q 'OK: Network namespaces (runtime namespace evidence present'
printf '%s\n' "$unknown_output" | grep -q 'NEEDS EVIDENCE: PIDs cgroup'
