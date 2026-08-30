#!/bin/sh
# Build an experimental DSM SPK archive from a reviewed dry-run payload.
# Does not install the package or execute DSM package scripts.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--payload DIRECTORY] [--output DIRECTORY]"
}

package_name=lxc-on-dsm
payload_dir=build/spk-payload/lxc-on-dsm
output_dir=build/spk

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --payload) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; payload_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
[ -d "$payload_dir" ] || { printf 'Missing payload directory: %s\n' "$payload_dir" >&2; exit 1; }
[ -r "${payload_dir}/INFO" ] || { printf 'Missing payload INFO: %s\n' "${payload_dir}/INFO" >&2; exit 1; }
[ -d "${payload_dir}/conf" ] || { printf 'Missing payload conf directory: %s\n' "${payload_dir}/conf" >&2; exit 1; }
[ -d "${payload_dir}/scripts" ] || { printf 'Missing payload scripts directory: %s\n' "${payload_dir}/scripts" >&2; exit 1; }
[ -d "${payload_dir}/target" ] || { printf 'Missing payload target directory: %s\n' "${payload_dir}/target" >&2; exit 1; }

version=$(sed -n 's/^version="//p' "${payload_dir}/INFO" | sed 's/"$//' | sed -n '1p')
[ -n "$version" ] || { printf 'Unable to read version from payload INFO\n' >&2; exit 1; }
case "$version" in *[!0-9._-]*|'') printf 'Invalid package version: %s\n' "$version" >&2; exit 1 ;; esac

mkdir -p "$output_dir"
spk_file="${output_dir}/${package_name}-${version}.spk"
[ ! -e "$spk_file" ] || { printf 'SPK already exists, refusing to overwrite: %s\n' "$spk_file" >&2; exit 1; }

tmp_package="${payload_dir}/package.tgz"
[ ! -e "$tmp_package" ] || { printf 'Payload already contains package.tgz, refusing to overwrite: %s\n' "$tmp_package" >&2; exit 1; }

tar -czf "$tmp_package" -C "${payload_dir}/target" .
tar -cf "$spk_file" -C "$payload_dir" INFO conf scripts package.tgz
rm -f "$tmp_package"

printf '%s\n' '# Experimental SPK build'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'version=%s\n' "$version"
printf 'payload=%s\n' "$payload_dir"
printf 'spk=%s\n' "$spk_file"
printf '\n'
printf '%s\n' 'Result: SPK BUILT. No package was installed and no package scripts were executed.'
