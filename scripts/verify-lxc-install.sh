#!/bin/sh
# Verify an installed LXC lab prefix without starting containers.
set -eu

usage() { printf '%s\n' "Usage: $0 --prefix DIRECTORY"; }
prefix=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { usage >&2; exit 2; }
case "$prefix" in
    /*) ;;
    *) printf 'Prefix must be an absolute path: %s\n' "$prefix" >&2; exit 2 ;;
esac

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
export PATH
if [ -d "${prefix}/lib" ]; then
    LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export LD_LIBRARY_PATH
fi

missing=0
check_binary() {
    name=$1
    path=$(command -v "$name" 2>/dev/null || true)
    if [ -z "$path" ]; then
        printf 'MISSING: %s\n' "$name"
        missing=$((missing + 1))
        return
    fi
    printf 'OK: %s -> %s\n' "$name" "$path"
}

printf '%s\n' '# LXC lab install verification'
printf '\n'
printf 'prefix=%s\n' "$prefix"
printf '\n'

for binary in lxc-start lxc-info lxc-monitor lxc-ls lxc-checkconfig lxc-attach lxc-stop; do
    check_binary "$binary"
done

if [ "$missing" -gt 0 ]; then
    printf '\nResult: BLOCKED (%s missing binary/binaries).\n' "$missing"
    exit 1
fi

printf '\n'
lxc-start --version
lxc-info --version
lxc-ls --version
printf '\nResult: INSTALLED USERSPACE OK. No container was started.\n'
printf 'For direct shell use, run: eval "$(sh scripts/print-lxc-env.sh --prefix %s)"\n' "$prefix"
