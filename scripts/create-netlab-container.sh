#!/bin/sh
# Create a stopped Alpine network lab container. Does not start it.
set -eu
PATH="/opt/bin:/opt/sbin:${PATH}"

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY [--name NAME] [--state-dir DIRECTORY] [--manifest FILE] [--sources DIRECTORY] [--network-type empty]"
}

prefix=""
name=alpine-netlab
state_dir=/volume1/@lxc/lab/containers
manifest=manifests/lxc-userspace.env
sources_dir="${PWD}/build/sources"
network_type=empty
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${script_dir}/lib/lab-config.sh"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --manifest) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; manifest=$2; shift 2 ;;
        --sources) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; sources_dir=$2; shift 2 ;;
        --network-type) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; network_type=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { usage >&2; exit 2; }
[ -r "$manifest" ] || { printf 'Missing manifest: %s\n' "$manifest" >&2; exit 2; }
. "$manifest"

case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 2 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac
case "$network_type" in
    empty) ;;
    *) printf 'Unsupported network type for this gate: %s\n' "$network_type" >&2; exit 2 ;;
esac

rootfs_tar="${sources_dir}/alpine-minirootfs-${ALPINE_MINIROOTFS_VERSION}-x86_64.tar.gz"
[ -r "$rootfs_tar" ] || {
    printf 'Missing Alpine rootfs tarball: %s\nRun scripts/fetch-sources.sh first.\n' "$rootfs_tar" >&2
    exit 1
}

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"
[ ! -e "$container_dir" ] || {
    printf 'Container already exists: %s\n' "$container_dir" >&2
    exit 1
}

mkdir -p "$rootfs_dir"
gzip -dc "$rootfs_tar" | tar -xf - -C "$rootfs_dir"

write_lab_config_with_network "$config_file" "$name" "$rootfs_dir" "$network_type"

printf 'Created stopped network lab container: %s\n' "$container_dir"
printf 'Config: %s\n' "$config_file"
printf 'Network type: %s\n' "$network_type"
printf 'No container was started.\n'
