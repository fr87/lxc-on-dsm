#!/bin/sh
# Inspect LXC runtime state for a lab container without starting it.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY [--name NAME] [--state-dir DIRECTORY]"
}

prefix=""
name=alpine-lab
state_dir=/volume1/@lxc/lab/containers
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

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }

printf '%s\n' '# LXC lab runtime verification'
printf '\n'
printf 'container=%s\n' "$name"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf '\n'
if ! lxc-info -P "$state_dir" -n "$name"; then
    printf '\nResult: FAILED TO LOAD CONTAINER CONFIG. No container was started.\n' >&2
    exit 1
fi
printf '\nConfig network lines:\n'
grep -E '^lxc\.net\.|^lxc\.start\.auto' "$config_file"
printf '\nResult: STOPPED CONTAINER CONFIG LOADS OK. No container was started.\n'
