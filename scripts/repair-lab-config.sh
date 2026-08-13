#!/bin/sh
# Rewrite an existing Phase 3 lab container config without touching rootfs.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY [--name NAME] [--state-dir DIRECTORY]"
}

prefix=""
name=alpine-lab
state_dir=/volume1/@lxc/lab/containers
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${script_dir}/lib/lab-config.sh"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { usage >&2; exit 2; }
case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 2 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"

[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }
[ -e "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }

backup_file="${config_file}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
cp "$config_file" "$backup_file"
write_lab_config "$config_file" "$name" "$rootfs_dir"

printf 'Rewrote lab container config: %s\n' "$config_file"
printf 'Previous config backup: %s\n' "$backup_file"
printf 'Rootfs was not modified.\n'
