#!/bin/sh
# Create a portable LXC lab runtime bundle from the validated prefix.
# Does not include containers or rootfs data.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--prefix DIRECTORY] [--output DIRECTORY]"
}

prefix=/volume1/@lxc/lab/opt
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$prefix" in
    /volume[0-9]*/@lxc/lab/opt) ;;
    *) printf 'Refusing unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;;
esac

[ -d "$prefix" ] || { printf 'Missing LXC prefix: %s\n' "$prefix" >&2; exit 1; }
for binary in lxc-start lxc-info lxc-ls lxc-stop lxc-checkconfig; do
    [ -x "${prefix}/bin/${binary}" ] || { printf 'Missing required LXC binary: %s\n' "${prefix}/bin/${binary}" >&2; exit 1; }
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
bundle_name="lxc-runtime-bundle-${stamp}"
bundle_dir="${output_dir}/${bundle_name}"
archive_file="${output_dir}/${bundle_name}.tar.gz"

[ ! -e "$bundle_dir" ] || { printf 'Bundle directory already exists: %s\n' "$bundle_dir" >&2; exit 1; }
[ ! -e "$archive_file" ] || { printf 'Bundle archive already exists: %s\n' "$archive_file" >&2; exit 1; }

mkdir -p "${bundle_dir}/runtime" "${bundle_dir}/observations"

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

{
    printf '%s\n' '# LXC runtime bundle manifest'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'source_prefix=%s\n' "$prefix"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '%s\n' '- runtime prefix only'
    printf '%s\n' '- does not include containers'
    printf '%s\n' '- does not include container rootfs data'
    printf '%s\n' '- does not start containers'
    printf '\n'
    printf '%s\n' '## Version evidence'
    printf 'lxc_start_version=%s\n' "$(lxc-start --version 2>/dev/null || printf unknown)"
    printf 'lxc_info_version=%s\n' "$(lxc-info --version 2>/dev/null || printf unknown)"
    printf 'lxc_ls_version=%s\n' "$(lxc-ls --version 2>/dev/null || printf unknown)"
} >"${bundle_dir}/MANIFEST.txt"

{
    printf '%s\n' '# LXC prefix file listing'
    printf '\n'
    find "$prefix" -mindepth 1 -print | sort
} >"${bundle_dir}/observations/source-prefix-files.txt"

tar -cf - -C "$prefix" . | tar -xf - -C "${bundle_dir}/runtime"

if find "${bundle_dir}/runtime" -path '*/containers' -o -path '*/containers/*' -o -path '*/containers/*/rootfs' -o -path '*/containers/*/rootfs/*' | grep -q .; then
    printf '%s\n' 'Refusing runtime bundle that appears to contain container state/rootfs data' >&2
    exit 1
fi

{
    printf '%s\n' '# Bundled runtime file listing'
    printf '\n'
    find "${bundle_dir}/runtime" -mindepth 1 -print | sort
} >"${bundle_dir}/observations/bundled-runtime-files.txt"

if command -v sha256sum >/dev/null 2>&1; then
    (
        cd "$bundle_dir"
        find . -type f ! -name SHA256SUMS -print | sort | xargs sha256sum
    ) >"${bundle_dir}/SHA256SUMS"
fi

tar -czf "$archive_file" -C "$output_dir" "$bundle_name"

printf '%s\n' '# LXC runtime bundle'
printf '\n'
printf 'source_prefix=%s\n' "$prefix"
printf 'bundle_dir=%s\n' "$bundle_dir"
printf 'archive=%s\n' "$archive_file"
printf '\n'
printf '%s\n' 'Result: LXC RUNTIME BUNDLE CREATED. No container or network state was changed.'
