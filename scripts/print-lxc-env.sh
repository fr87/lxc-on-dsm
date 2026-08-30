#!/bin/sh
# Print shell exports needed to run LXC binaries from a lab prefix.
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

quote_for_shell() {
    printf "%s" "$1" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/"
}

new_path="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
printf 'export PATH=%s\n' "$(quote_for_shell "$new_path")"
if [ -d "${prefix}/lib" ]; then
    new_ld_library_path="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    printf 'export LD_LIBRARY_PATH=%s\n' "$(quote_for_shell "$new_ld_library_path")"
fi
