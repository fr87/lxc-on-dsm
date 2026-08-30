#!/bin/sh
# Verify a local macvlan lab profile without starting containers or changing networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--profile FILE]"
}

profile_file=config/lab-macvlan.env

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -r "$profile_file" ] || { printf 'Missing profile: %s\n' "$profile_file" >&2; exit 1; }
. "$profile_file"

prefix=${LXC_LAB_PREFIX:-}
state_dir=${LXC_LAB_STATE_DIR:-}
name=${LXC_LAB_CONTAINER:-}
parent_if=${LXC_LAB_PARENT_IF:-}
shim_if=${LXC_LAB_SHIM_IF:-}
host_cidr=${LXC_LAB_HOST_SHIM_CIDR:-}

[ -n "$prefix" ] || { printf 'Profile missing LXC_LAB_PREFIX\n' >&2; exit 1; }
[ -n "$state_dir" ] || { printf 'Profile missing LXC_LAB_STATE_DIR\n' >&2; exit 1; }
[ -n "$name" ] || { printf 'Profile missing LXC_LAB_CONTAINER\n' >&2; exit 1; }
[ -n "$parent_if" ] || { printf 'Profile missing LXC_LAB_PARENT_IF\n' >&2; exit 1; }
[ -n "$shim_if" ] || { printf 'Profile missing LXC_LAB_SHIM_IF\n' >&2; exit 1; }
case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 1 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 1 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 1 ;; esac
case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface: %s\n' "$parent_if" >&2; exit 1 ;; esac
case "$shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid shim interface: %s\n' "$shim_if" >&2; exit 1 ;; esac
case "$host_cidr" in *[!A-Za-z0-9_./:-]*) printf 'Invalid host shim CIDR: %s\n' "$host_cidr" >&2; exit 1 ;; esac

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
rootfs_dir="${container_dir}/rootfs"

printf '%s\n' '# Macvlan lab profile verification'
printf '\n'
printf 'profile=%s\n' "$profile_file"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'container=%s\n' "$name"
printf 'parent_if=%s\n' "$parent_if"
printf 'shim_if=%s\n' "$shim_if"
printf 'host_cidr=%s\n' "$host_cidr"
printf '\n'

status=0
warns=0

check_ok() {
    printf 'OK: %s\n' "$1"
}

check_warn() {
    warns=$((warns + 1))
    printf 'WARN: %s\n' "$1"
}

check_fail() {
    status=1
    printf 'FAIL: %s\n' "$1"
}

[ -x "${prefix}/bin/lxc-start" ] && check_ok "lxc-start exists under prefix" || check_fail "lxc-start missing under prefix"
[ -x "${prefix}/bin/lxc-info" ] && check_ok "lxc-info exists under prefix" || check_fail "lxc-info missing under prefix"
[ -r "$config_file" ] && check_ok "container config exists" || check_fail "container config missing: $config_file"
[ -d "$rootfs_dir" ] && check_ok "container rootfs exists" || check_fail "container rootfs missing: $rootfs_dir"

if [ -r "$config_file" ]; then
    grep -q '^lxc\.net\.0\.type = macvlan$' "$config_file" && check_ok "container is configured for macvlan" || check_fail "container is not configured for macvlan"
    grep -Fqx "lxc.net.0.link = ${parent_if}" "$config_file" && check_ok "container parent interface matches profile" || check_fail "container parent interface does not match profile"
    grep -q '^lxc\.start\.auto = 0$' "$config_file" && check_ok "container autostart is disabled" || check_warn "container autostart is not explicitly disabled"
fi

if command -v ip >/dev/null 2>&1; then
    ip link show "$parent_if" >/dev/null 2>&1 && check_ok "parent interface exists" || check_fail "parent interface missing: $parent_if"
    if ip link show "$shim_if" >/dev/null 2>&1; then
        check_warn "shim interface already exists; lifecycle scripts should not take it over automatically"
    else
        check_ok "shim interface is absent before lifecycle use"
    fi
else
    check_fail "ip command missing"
fi

if [ -n "$host_cidr" ]; then
    check_ok "host shim CIDR configured"
else
    check_warn "host shim CIDR is empty; host-to-container shim lifecycle cannot run until configured"
fi

printf '\n'
if [ "$status" -eq 0 ]; then
    printf 'Result: MACVLAN PROFILE VERIFIED'
    [ "$warns" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warns"
    printf '. No container was started and no networking was changed.\n'
else
    printf 'Result: MACVLAN PROFILE NOT READY. No container was started and no networking was changed.\n'
fi

exit "$status"
