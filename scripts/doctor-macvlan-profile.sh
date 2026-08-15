#!/bin/sh
# Inspect macvlan lifecycle state without starting containers or changing networking.
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
profile_shim_if=${LXC_LAB_SHIM_IF:-}
profile_host_cidr=${LXC_LAB_HOST_SHIM_CIDR:-}

[ -n "$prefix" ] || { printf 'Profile missing LXC_LAB_PREFIX\n' >&2; exit 1; }
[ -n "$state_dir" ] || { printf 'Profile missing LXC_LAB_STATE_DIR\n' >&2; exit 1; }
[ -n "$name" ] || { printf 'Profile missing LXC_LAB_CONTAINER\n' >&2; exit 1; }
[ -n "$parent_if" ] || { printf 'Profile missing LXC_LAB_PARENT_IF\n' >&2; exit 1; }
[ -n "$profile_shim_if" ] || { printf 'Profile missing LXC_LAB_SHIM_IF\n' >&2; exit 1; }
case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 1 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 1 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 1 ;; esac
case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface: %s\n' "$parent_if" >&2; exit 1 ;; esac
case "$profile_shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid shim interface: %s\n' "$profile_shim_if" >&2; exit 1 ;; esac
case "$profile_host_cidr" in *[!A-Za-z0-9_./:-]*) printf 'Invalid host shim CIDR: %s\n' "$profile_host_cidr" >&2; exit 1 ;; esac

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
rootfs_dir="${container_dir}/rootfs"
runtime_state="${container_dir}/lifecycle-state.env"

runtime_shim_if=
runtime_host_cidr=
runtime_container_ip=
runtime_route_added=0
runtime_shim_created=0
runtime_dhcp_status=
runtime_log=

if [ -r "$runtime_state" ]; then
    . "$runtime_state"
    runtime_shim_if=${shim_if:-}
    runtime_host_cidr=${host_cidr:-}
    runtime_container_ip=${container_ip:-}
    runtime_route_added=${route_added:-0}
    runtime_shim_created=${shim_created:-0}
    runtime_dhcp_status=${dhcp_status:-}
    runtime_log=${log:-}
fi

shim_if=${runtime_shim_if:-$profile_shim_if}
case "$shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid effective shim interface: %s\n' "$shim_if" >&2; exit 1 ;; esac
case "$runtime_container_ip" in *[!A-Za-z0-9_.:-]*) printf 'Invalid runtime container IP: %s\n' "$runtime_container_ip" >&2; exit 1 ;; esac

problems=0
warnings=0

ok() {
    printf 'OK: %s\n' "$1"
}

warn() {
    warnings=$((warnings + 1))
    printf 'WARN: %s\n' "$1"
}

problem() {
    problems=$((problems + 1))
    printf 'PROBLEM: %s\n' "$1"
}

printf '%s\n' '# Macvlan lifecycle doctor'
printf '\n'
printf 'profile=%s\n' "$profile_file"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'container=%s\n' "$name"
printf 'parent_if=%s\n' "$parent_if"
printf 'profile_shim_if=%s\n' "$profile_shim_if"
printf 'effective_shim_if=%s\n' "$shim_if"
printf 'profile_host_cidr=%s\n' "$profile_host_cidr"
printf 'runtime_state=%s\n' "$runtime_state"
printf '\n'

[ -x "${prefix}/bin/lxc-info" ] && ok "lxc-info exists under prefix" || problem "lxc-info missing under prefix"
[ -x "${prefix}/bin/lxc-stop" ] && ok "lxc-stop exists under prefix" || warn "lxc-stop missing under prefix"
[ -r "$config_file" ] && ok "container config exists" || problem "container config missing: $config_file"
[ -d "$rootfs_dir" ] && ok "container rootfs exists" || problem "container rootfs missing: $rootfs_dir"

if [ -r "$config_file" ]; then
    grep -q '^lxc\.net\.0\.type = macvlan$' "$config_file" && ok "container is configured for macvlan" || problem "container is not configured for macvlan"
    grep -Fqx "lxc.net.0.link = ${parent_if}" "$config_file" && ok "container parent interface matches profile" || problem "container parent interface does not match profile"
    grep -q '^lxc\.start\.auto = 0$' "$config_file" && ok "container autostart is disabled" || warn "container autostart is not explicitly disabled"
fi

command -v ip >/dev/null 2>&1 && ok "ip command is present" || problem "ip command is missing"
if command -v ip >/dev/null 2>&1; then
    ip link show "$parent_if" >/dev/null 2>&1 && ok "parent interface exists" || problem "parent interface missing: $parent_if"
fi

container_state=UNKNOWN
if command -v lxc-info >/dev/null 2>&1; then
    container_state=$(lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | sed -n 's/^State:[[:space:]]*//p' | sed -n '1p')
    [ -n "$container_state" ] || container_state=UNKNOWN
fi

runtime_state_present=NO
if [ -r "$runtime_state" ]; then
    runtime_state_present=YES
    ok "runtime state exists"
else
    ok "runtime state is absent"
fi

shim_present=UNKNOWN
if command -v ip >/dev/null 2>&1; then
    if ip link show "$shim_if" >/dev/null 2>&1; then
        shim_present=YES
    else
        shim_present=NO
    fi
fi

route_present=UNKNOWN
if command -v ip >/dev/null 2>&1 && [ -n "$runtime_container_ip" ]; then
    if ip route show "${runtime_container_ip}/32" 2>/dev/null | grep -Fq "dev ${shim_if}"; then
        route_present=YES
    else
        route_present=NO
    fi
elif [ -z "$runtime_container_ip" ]; then
    route_present=NO_RUNTIME_IP
fi

printf '\n'
printf '%s\n' 'Runtime observations:'
printf 'container_state=%s\n' "$container_state"
printf 'runtime_state_present=%s\n' "$runtime_state_present"
printf 'runtime_container_ip=%s\n' "$runtime_container_ip"
printf 'runtime_dhcp_status=%s\n' "$runtime_dhcp_status"
printf 'runtime_shim_created=%s\n' "$runtime_shim_created"
printf 'runtime_route_added=%s\n' "$runtime_route_added"
printf 'runtime_log=%s\n' "$runtime_log"
printf 'shim_present=%s\n' "$shim_present"
printf 'route_present=%s\n' "$route_present"

printf '\n'
printf '%s\n' 'Doctor interpretation:'

case "$container_state" in
    RUNNING) ok "container is running" ;;
    STOPPED) ok "container is stopped" ;;
    UNKNOWN) warn "container state is unknown" ;;
    *) warn "container state is unexpected: $container_state" ;;
esac

if [ "$runtime_state_present" = YES ] && [ "$container_state" != RUNNING ]; then
    problem "runtime state exists but container is not RUNNING; stop script should archive stale state"
fi
if [ "$runtime_state_present" = NO ] && [ "$container_state" = RUNNING ]; then
    problem "container is RUNNING without lifecycle runtime state"
fi
if [ "$shim_present" = YES ] && [ "$runtime_state_present" = NO ]; then
    problem "shim interface exists without lifecycle runtime state"
fi
if [ "$runtime_shim_created" = 1 ] && [ "$shim_present" != YES ]; then
    problem "runtime state says shim was created but shim interface is absent"
fi
if [ "$runtime_route_added" = 1 ] && [ "$route_present" != YES ]; then
    problem "runtime state says route was added but route is absent"
fi
if [ "$runtime_route_added" != 1 ] && [ "$route_present" = YES ]; then
    problem "route exists but runtime state does not claim it"
fi
if [ "$profile_host_cidr" != "" ] && [ "$runtime_container_ip" != "" ]; then
    profile_host_ip=${profile_host_cidr%%/*}
    if [ "$profile_host_ip" = "$runtime_container_ip" ]; then
        problem "profile host shim IP equals runtime container IP"
    fi
fi
if [ "$runtime_state_present" = YES ] && [ "$profile_shim_if" != "$shim_if" ]; then
    warn "runtime shim interface differs from profile shim interface"
fi

printf '\n'
if [ "$problems" -eq 0 ]; then
    printf 'Result: MACVLAN DOCTOR PASS'
    [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
    printf '. No container was started and no networking was changed.\n'
else
    printf 'Result: MACVLAN DOCTOR FOUND %s PROBLEM(S)' "$problems"
    [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
    printf '. No container was started and no networking was changed.\n'
    exit 1
fi
