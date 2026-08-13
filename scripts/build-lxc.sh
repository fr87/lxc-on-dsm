#!/bin/sh
# Build pinned LXC sources under project-owned directories.
set -eu
PATH="/opt/bin:/opt/sbin:${PATH}"

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY [--manifest FILE] [--sources DIRECTORY] [--build DIRECTORY] [--install]"
}

manifest=manifests/lxc-userspace.env
sources_dir="${PWD}/build/sources"
build_dir="${PWD}/build/work"
prefix=""
install_after_build=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --manifest) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; manifest=$2; shift 2 ;;
        --sources) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; sources_dir=$2; shift 2 ;;
        --build) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; build_dir=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --install) install_after_build=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { usage >&2; exit 2; }
[ -r "$manifest" ] || { printf 'Missing manifest: %s\n' "$manifest" >&2; exit 2; }
. "$manifest"

for tool in meson ninja tar gzip sed awk grep; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'Missing required tool: %s\n' "$tool" >&2; exit 1; }
done
if command -v pkg-config >/dev/null 2>&1; then
    :
elif command -v pkgconf >/dev/null 2>&1; then
    PKG_CONFIG=$(command -v pkgconf)
    export PKG_CONFIG
else
    printf 'Missing required tool: pkg-config or pkgconf\n' >&2
    exit 1
fi
if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
    printf 'Missing required tool: cc or gcc\n' >&2
    exit 1
fi

case "$prefix" in
    /*) ;;
    *) printf 'Prefix must be an absolute path: %s\n' "$prefix" >&2; exit 2 ;;
esac

lxc_tar="${sources_dir}/lxc-${LXC_VERSION}.tar.gz"
[ -r "$lxc_tar" ] || {
    printf 'Missing source tarball: %s\nRun scripts/fetch-sources.sh first.\n' "$lxc_tar" >&2
    exit 1
}

src_parent="${build_dir}/src"
lxc_src="${src_parent}/lxc-${LXC_VERSION}"
lxc_build="${build_dir}/lxc-${LXC_VERSION}-build"
mkdir -p "$src_parent"

if [ ! -d "$lxc_src" ]; then
    gzip -dc "$lxc_tar" | tar -xf - -C "$src_parent"
fi

meson setup "$lxc_build" "$lxc_src" \
    --prefix "$prefix" \
    --sysconfdir etc \
    --localstatedir var \
    --libdir lib
ninja -C "$lxc_build"

if [ "$install_after_build" -eq 1 ]; then
    meson install -C "$lxc_build"
    printf 'LXC installed under %s\n' "$prefix"
else
    printf 'LXC build complete: %s\n' "$lxc_build"
    printf 'Install explicitly with: %s --prefix %s --install\n' "$0" "$prefix"
fi
