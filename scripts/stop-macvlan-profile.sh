#!/bin/sh
# Stop the profiled macvlan lab container and remove lifecycle-owned shim state.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--profile FILE] [--output DIRECTORY]"
}

profile_file=config/lab-macvlan.env
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -r "$profile_file" ] || { printf 'Missing profile: %s\n' "$profile_file" >&2; exit 1; }
. "$profile_file"

prefix=${LXC_LAB_PREFIX:-}
state_dir=${LXC_LAB_STATE_DIR:-}
name=${LXC_LAB_CONTAINER:-}
profile_shim_if=${LXC_LAB_SHIM_IF:-}

[ -n "$prefix" ] || { printf 'Profile missing LXC_LAB_PREFIX\n' >&2; exit 1; }
[ -n "$state_dir" ] || { printf 'Profile missing LXC_LAB_STATE_DIR\n' >&2; exit 1; }
[ -n "$name" ] || { printf 'Profile missing LXC_LAB_CONTAINER\n' >&2; exit 1; }
[ -n "$profile_shim_if" ] || { printf 'Profile missing LXC_LAB_SHIM_IF\n' >&2; exit 1; }
case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 1 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 1 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 1 ;; esac
case "$profile_shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid shim interface: %s\n' "$profile_shim_if" >&2; exit 1 ;; esac

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

command -v ip >/dev/null 2>&1 || { printf 'Missing host ip command\n' >&2; exit 1; }
command -v lxc-stop >/dev/null 2>&1 || { printf 'Missing lxc-stop command\n' >&2; exit 1; }
command -v lxc-info >/dev/null 2>&1 || { printf 'Missing lxc-info command\n' >&2; exit 1; }

container_dir="${state_dir}/${name}"
runtime_state="${container_dir}/lifecycle-state.env"
profile_state_dir=$state_dir
profile_name=$name
shim_if=$profile_shim_if
container_ip=
route_added=0
shim_created=0

if [ -r "$runtime_state" ]; then
    . "$runtime_state"
    state_dir=$profile_state_dir
    name=$profile_name
    shim_if=${shim_if:-$profile_shim_if}
    container_ip=${container_ip:-}
    route_added=${route_added:-0}
    shim_created=${shim_created:-0}
fi

case "$shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid runtime shim interface: %s\n' "$shim_if" >&2; exit 1 ;; esac
case "$container_ip" in *[!A-Za-z0-9_.:-]*) printf 'Invalid runtime container IP: %s\n' "$container_ip" >&2; exit 1 ;; esac

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-lifecycle-stop-${name}-${stamp}.log"

{
    printf '%s\n' '# LXC macvlan lifecycle stop'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'profile=%s\n' "$profile_file"
    printf 'container=%s\n' "$name"
    printf 'runtime_state=%s\n' "$runtime_state"
    printf 'shim_if=%s\n' "$shim_if"
    printf 'container_ip=%s\n' "$container_ip"
    printf 'route_added=%s\n' "$route_added"
    printf 'shim_created=%s\n' "$shim_created"
    printf '\n## cleanup\n'
} >"$log_file"

if [ "$route_added" = 1 ] && [ -n "$container_ip" ]; then
    ip route del "${container_ip}/32" dev "$shim_if" >>"$log_file" 2>&1 || true
fi

if [ "$shim_created" = 1 ]; then
    ip link set "$shim_if" down >>"$log_file" 2>&1 || true
    ip link del "$shim_if" >>"$log_file" 2>&1 || true
elif ip link show "$shim_if" >/dev/null 2>&1; then
    printf 'WARN: shim interface exists but no lifecycle state claims ownership: %s\n' "$shim_if" | tee -a "$log_file" >&2
fi

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
fi

stopped=NO
if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    stopped=NO
else
    stopped=YES
fi

shim_absent=NO
if ip link show "$shim_if" >/dev/null 2>&1; then
    shim_absent=NO
else
    shim_absent=YES
fi

if [ -e "$runtime_state" ]; then
    mv "$runtime_state" "${runtime_state}.previous.${stamp}"
fi

printf '%s\n' '# LXC macvlan lifecycle stop summary'
printf '\n'
printf 'profile=%s\n' "$profile_file"
printf 'container=%s\n' "$name"
printf 'shim_if=%s\n' "$shim_if"
printf 'container_stopped=%s\n' "$stopped"
printf 'shim_absent=%s\n' "$shim_absent"
printf 'log=%s\n' "$log_file"
printf '\n'

if [ "$stopped" = YES ] && [ "$shim_absent" = YES ]; then
    printf '%s\n' 'Result: MACVLAN LIFECYCLE STOPPED. Container stopped and lifecycle-owned shim removed.'
else
    printf '%s\n' 'Result: MACVLAN LIFECYCLE STOP INCOMPLETE. Inspect log and host state.'
    exit 1
fi
