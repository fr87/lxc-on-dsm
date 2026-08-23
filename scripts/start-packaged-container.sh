#!/bin/sh
# Start a package-created lab container and keep it running. Dry-run by default.
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
    [ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged container start requires uid=0.' >&2; exit 1; }
fi

PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib:${prefix}/lib64:${LD_LIBRARY_PATH:-}"
LXC_CONFIG_PATH="$state_dir"
export PATH LD_LIBRARY_PATH LXC_CONFIG_PATH

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"
runtime_state="${container_dir}/packaged-start-state.env"

[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }
grep -q '^lxc\.start\.auto = 0$' "$config_file" || {
    printf '%s\n' 'Refusing packaged start because container is not configured with lxc.start.auto = 0.' >&2
    exit 1
}
network_type=$(sed -n 's/^lxc\.net\.0\.type = //p' "$config_file" | sed -n '1p')
case "$network_type" in empty|macvlan) ;; none) printf '%s\n' 'Refusing persistent start for lxc.net.0.type = none. Use the smoke test for none, or create the container with --network-type empty or macvlan.' >&2; exit 1 ;; *) printf 'Unsupported network type for packaged start: %s\n' "$network_type" >&2; exit 1 ;; esac
parent_if=
if [ "$network_type" = macvlan ]; then
    parent_if=$(sed -n 's/^lxc\.net\.0\.link = //p' "$config_file" | sed -n '1p')
    [ -n "$parent_if" ] || { printf 'Missing macvlan parent in config: %s\n' "$config_file" >&2; exit 1; }
    case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface in config: %s\n' "$parent_if" >&2; exit 1 ;; esac
    command -v ip >/dev/null 2>&1 || { printf 'Missing host ip command\n' >&2; exit 1; }
    ip link show "$parent_if" >/dev/null 2>&1 || { printf 'Parent interface missing: %s\n' "$parent_if" >&2; exit 1; }
fi

printf '%s\n' '# Packaged LXC container start plan'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'run=%s\n' "$run"
printf 'container=%s\n' "$name"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'network_type=%s\n' "$network_type"
[ -z "$parent_if" ] || printf 'parent_if=%s\n' "$parent_if"
printf 'runtime_state=%s\n' "$runtime_state"
printf 'output=%s\n' "$output_dir"
printf '\n'

if [ "$run" -ne 1 ]; then
    printf '%s\n' 'Result: PACKAGED CONTAINER START DRY RUN COMPLETE. No container was started and no networking was changed.'
    exit 0
fi

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running: %s\n' "$name" >&2
    exit 1
fi

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-packaged-start-${name}-${stamp}.log"
lxc_debug_log="${output_dir}/lxc-packaged-start-${name}-${stamp}.debug.log"
evidence_name="dsm-lxc-packaged-start-${stamp}.env"
evidence_file="${rootfs_dir}/tmp/${evidence_name}"

{
    printf '%s\n' '# Packaged LXC container start'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'network_type=%s\n' "$network_type"
    [ -z "$parent_if" ] || printf 'parent_if=%s\n' "$parent_if"
    printf 'lxc_debug_log=%s\n' "$lxc_debug_log"
    printf 'evidence_file=%s\n' "$evidence_file"
    printf '\n## config network lines\n'
    grep -E '^lxc\.net\.|^lxc\.start\.auto' "$config_file" || true
    printf '\n## detached container start\n'
} >"$log_file"

if ! lxc-start -d -P "$state_dir" -n "$name" --logfile "$lxc_debug_log" --logpriority DEBUG -- /bin/sh -c '
    evidence=/tmp/'"$evidence_name"'
    dhcp_status=SKIPPED
    if [ "'"$network_type"'" = macvlan ] && command -v udhcpc >/dev/null 2>&1; then
        udhcpc -i eth0 -n -q -t 3 -T 3 >/tmp/udhcpc-packaged-start.log 2>&1 && dhcp_status=OK || dhcp_status=FAIL
    fi
    ip_addr=
    if [ "'"$network_type"'" = macvlan ]; then
        ip_addr=$(ip -4 -o addr show dev eth0 2>/dev/null | awk "{print \$4; exit}" || true)
    fi
    ip_plain=${ip_addr%%/*}
    gateway=$(ip route 2>/dev/null | awk "/^default / {print \$3; exit}" || true)
    {
        printf "generated_utc=%s\n" "'"$stamp"'"
        printf "dhcp_status=%s\n" "$dhcp_status"
        printf "ip_addr=%s\n" "$ip_addr"
        printf "ip_plain=%s\n" "$ip_plain"
        printf "gateway=%s\n" "$gateway"
        printf "routes=%s\n" "$(ip route 2>/dev/null | tr "\n" "|" || true)"
    } >"$evidence"
    trap "exit 0" TERM INT
    while :; do sleep 3600; done
' >>"$log_file" 2>&1; then
    printf 'Packaged container start failed; inspect log: %s\n' "$log_file" >&2
    exit 1
fi

i=0
while [ "$i" -lt 15 ]; do
    [ -r "$evidence_file" ] && break
    i=$((i + 1))
    sleep 1
done

[ -r "$evidence_file" ] || { printf 'Container did not write start evidence: %s\n' "$evidence_file" >&2; exit 1; }
cat "$evidence_file" >>"$log_file"
dhcp_status=$(sed -n 's/^dhcp_status=//p' "$evidence_file" | sed -n '1p')
container_ip=$(sed -n 's/^ip_plain=//p' "$evidence_file" | sed -n '1p')
gateway=$(sed -n 's/^gateway=//p' "$evidence_file" | sed -n '1p')

{
    printf '%s\n' '# Packaged LXC container runtime state'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'network_type=%s\n' "$network_type"
    [ -z "$parent_if" ] || printf 'parent_if=%s\n' "$parent_if"
    printf 'container_ip=%s\n' "$container_ip"
    printf 'gateway=%s\n' "$gateway"
    printf 'dhcp_status=%s\n' "$dhcp_status"
    printf 'log=%s\n' "$log_file"
    printf 'lxc_debug_log=%s\n' "$lxc_debug_log"
} >"$runtime_state"

printf '%s\n' '# Packaged LXC container start summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'network_type=%s\n' "$network_type"
[ -z "$parent_if" ] || printf 'parent_if=%s\n' "$parent_if"
printf 'container_ip=%s\n' "$container_ip"
printf 'gateway=%s\n' "$gateway"
printf 'dhcp_status=%s\n' "$dhcp_status"
printf 'runtime_state=%s\n' "$runtime_state"
printf 'log=%s\n' "$log_file"
printf 'lxc_debug_log=%s\n' "$lxc_debug_log"
printf '\n'
printf '%s\n' 'Result: PACKAGED CONTAINER STARTED. Stop with stop-packaged-container.sh.'
