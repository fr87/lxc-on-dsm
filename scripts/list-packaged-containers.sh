#!/bin/sh
# List package-owned LXC lab containers. Read-only: no container start, no network changes.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--prefix DIRECTORY] [--state-dir DIRECTORY]"
}

prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$prefix" in /volume[0-9]*/@lxc/lab/opt) ;; *) printf 'Unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /volume[0-9]*/@lxc/lab/containers) ;; *) printf 'Unexpected state dir: %s\n' "$state_dir" >&2; exit 2 ;; esac

lxc_info="${prefix}/bin/lxc-info"
PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib:${prefix}/lib64:${LD_LIBRARY_PATH:-}"
LXC_CONFIG_PATH="$state_dir"
export PATH LD_LIBRARY_PATH LXC_CONFIG_PATH

printf '%s\n' '# Packaged LXC container inventory'
printf '\n'
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf '\n'

if [ ! -d "$state_dir" ]; then
    printf '%s\n' 'containers=0'
    printf '\n'
    printf '%s\n' 'Result: PACKAGED CONTAINER INVENTORY COMPLETE. State directory is absent. No container was started and no networking was changed.'
    exit 0
fi

count=0
for container_dir in "$state_dir"/*; do
    [ -d "$container_dir" ] || continue
    name=${container_dir##*/}
    case "$name" in *[!A-Za-z0-9_.-]*|'') continue ;; esac
    config_file="${container_dir}/config"
    rootfs_dir="${container_dir}/rootfs"
    [ -r "$config_file" ] || continue
    count=$((count + 1))

    network_type=$(sed -n 's/^lxc\.net\.0\.type[[:space:]]*=[[:space:]]*//p' "$config_file" | sed -n '1p')
    parent_if=$(sed -n 's/^lxc\.net\.0\.link[[:space:]]*=[[:space:]]*//p' "$config_file" | sed -n '1p')
    autostart=$(sed -n 's/^lxc\.start\.auto[[:space:]]*=[[:space:]]*//p' "$config_file" | sed -n '1p')
    rootfs_present=no
    [ -d "$rootfs_dir" ] && rootfs_present=yes
    state=UNKNOWN
    if [ -x "$lxc_info" ]; then
        state_line=$("$lxc_info" -P "$state_dir" -n "$name" 2>/dev/null | sed -n 's/^State:[[:space:]]*//p' | sed -n '1p' || true)
        [ -z "$state_line" ] || state=$state_line
    fi

    printf '[%s]\n' "$name"
    printf 'state=%s\n' "$state"
    printf 'network_type=%s\n' "${network_type:-unknown}"
    [ -z "$parent_if" ] || printf 'parent_if=%s\n' "$parent_if"
    printf 'autostart=%s\n' "${autostart:-unknown}"
    printf 'rootfs_present=%s\n' "$rootfs_present"
    printf 'config=%s\n' "$config_file"
    printf '\n'
done

printf 'containers=%s\n' "$count"
printf '\n'
printf '%s\n' 'Result: PACKAGED CONTAINER INVENTORY COMPLETE. No container was started and no networking was changed.'
