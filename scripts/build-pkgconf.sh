#!/bin/sh
# Build pkgconf as a bootstrap dependency when Entware does not provide it.
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

for tool in tar xz sed awk grep make; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'Missing required tool: %s\n' "$tool" >&2; exit 1; }
done
if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
    printf 'Missing required tool: cc or gcc\n' >&2
    exit 1
fi

case "$prefix" in
    /*) ;;
    *) printf 'Prefix must be an absolute path: %s\n' "$prefix" >&2; exit 2 ;;
esac

pkgconf_tar="${sources_dir}/pkgconf-${PKGCONF_VERSION}.tar.xz"
[ -r "$pkgconf_tar" ] || {
    printf 'Missing source tarball: %s\nRun scripts/fetch-sources.sh first.\n' "$pkgconf_tar" >&2
    exit 1
}

src_parent="${build_dir}/src"
pkgconf_src="${src_parent}/pkgconf-${PKGCONF_VERSION}"
pkgconf_build="${build_dir}/pkgconf-${PKGCONF_VERSION}-build"
mkdir -p "$src_parent" "$pkgconf_build"

if [ ! -d "$pkgconf_src" ]; then
    xz -dc "$pkgconf_tar" | tar -xf - -C "$src_parent"
fi

cd "$pkgconf_build"
"${pkgconf_src}/configure" --prefix="$prefix" --with-pkg-config-dir="${prefix}/lib/pkgconfig:${prefix}/share/pkgconfig:/opt/lib/pkgconfig:/opt/share/pkgconfig"
make

if [ "$install_after_build" -eq 1 ]; then
    make install
    if [ ! -e "${prefix}/bin/pkg-config" ] && [ -x "${prefix}/bin/pkgconf" ]; then
        ln -s pkgconf "${prefix}/bin/pkg-config"
    fi
    printf 'pkgconf installed under %s\n' "$prefix"
else
    printf 'pkgconf build complete: %s\n' "$pkgconf_build"
    printf 'Install explicitly with: %s --prefix %s --install\n' "$0" "$prefix"
fi
