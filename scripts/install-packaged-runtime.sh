#!/bin/sh
# Restore the runtime bundle shipped inside the installed SPK.
# Default mode is dry-run; pass --install to write /volumeN/@lxc/lab/opt.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--target DIRECTORY] [--output DIRECTORY] [--install]"
}

package_name=lxc-on-dsm
target_prefix=/volume1/@lxc/lab/opt
output_dir=
install_arg=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --target) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; target_prefix=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --install) install_arg=--install; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
case "$target_prefix" in
    /volume[0-9]*/@lxc/lab/opt) ;;
    *) printf 'Refusing unexpected LXC target prefix: %s\n' "$target_prefix" >&2; exit 2 ;;
esac

pkg_target="/var/packages/${package_name}/target"
pkg_var="/var/packages/${package_name}/var"
[ -n "$output_dir" ] || output_dir="${pkg_var}/artifacts"

bundle="${pkg_target}/runtime/lxc-runtime-bundle.tar.gz"
restore_script="${pkg_target}/scripts/restore-lxc-runtime-bundle.sh"

[ -r "$bundle" ] || { printf 'Missing packaged runtime bundle: %s\n' "$bundle" >&2; exit 1; }
[ -r "$restore_script" ] || { printf 'Missing packaged restore script: %s\n' "$restore_script" >&2; exit 1; }

printf '%s\n' '# Packaged LXC runtime restore'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'bundle=%s\n' "$bundle"
printf 'target_prefix=%s\n' "$target_prefix"
printf 'output=%s\n' "$output_dir"
printf 'install=%s\n' "${install_arg:+1}"
printf '\n'

exec sh "$restore_script" \
    --bundle "$bundle" \
    --target "$target_prefix" \
    --output "$output_dir" \
    ${install_arg:+"$install_arg"}
