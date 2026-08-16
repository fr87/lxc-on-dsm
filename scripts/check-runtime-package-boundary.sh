#!/bin/sh
# Check that a runtime directory or bundle does not contain build-only tooling.
# Does not install, restore, execute runtime binaries or start containers.
set -eu

usage() {
    printf '%s\n' "Usage: $0 PATH"
}

[ "$#" -eq 1 ] || { usage >&2; exit 2; }
case "$1" in
    -h|--help) usage; exit 0 ;;
esac

input_path=$1
[ -e "$input_path" ] || { printf 'Missing path: %s\n' "$input_path" >&2; exit 1; }

tmp_dir=
cleanup() {
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ -d "$input_path" ]; then
    check_dir=$input_path
else
    case "$input_path" in
        *.tar.gz|*.tgz) ;;
        *) printf 'Archive must end with .tar.gz or .tgz: %s\n' "$input_path" >&2; exit 1 ;;
    esac
    tmp_dir=$(mktemp -d)
    tar -xzf "$input_path" -C "$tmp_dir"
    check_dir=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
    [ -n "$check_dir" ] || { printf 'Archive did not contain a top-level directory\n' >&2; exit 1; }
fi

problems=0
warnings=0

ok() {
    printf 'OK: %s\n' "$1"
}

warn() {
    warnings=$((warnings + 1))
    printf 'WARN: %s\n' "$1"
}

problem() {
    problems=$((problems + 1))
    printf 'PROBLEM: %s\n' "$1"
}

printf '%s\n' '# Runtime package boundary check'
printf '\n'
printf 'path=%s\n' "$input_path"
printf 'check_dir=%s\n' "$check_dir"
printf '\n'

blocked_names='
gcc
g++
cc
c++
make
meson
ninja
pkg-config
pkgconf
opkg
'

for name in $blocked_names; do
    if find "$check_dir" -type f -name "$name" -print | grep -q .; then
        problem "build/package manager tool present: $name"
    else
        ok "no $name tool present"
    fi
done

if find "$check_dir" \( -name '*.o' -o -name 'meson-private' -o -name 'meson-info' -o -name 'build.ninja' \) -print | grep -q .; then
    problem "build intermediate artifacts are present"
else
    ok "no common build intermediate artifacts present"
fi

if find "$check_dir" \( -name '*.a' -o -name '*.la' \) -print | grep -q .; then
    warn "static/libtool library metadata is present; strip from final package if not needed"
else
    ok "no static/libtool library metadata detected"
fi

if find "$check_dir" -path '*/build/work/*' -o -path '*/build/sources/*' -o -path '*/src/lxc-*' | grep -q .; then
    problem "source/build tree appears to be present"
else
    ok "no source/build tree detected"
fi

if find "$check_dir" -path '*/opkg/*' -o -path '*/var/opkg/*' -o -path '*/var/opkg-lists/*' | grep -q .; then
    problem "Entware/opkg package manager state is present"
else
    ok "no Entware/opkg package manager state detected"
fi

if grep -RIl '/opt/lib/ld-linux-x86-64.so.2' "$check_dir" >/tmp/lxc-on-dsm-runtime-boundary.$$ 2>/dev/null; then
    cat /tmp/lxc-on-dsm-runtime-boundary.$$
    problem "runtime contains Entware /opt loader reference"
else
    ok "no Entware /opt loader reference detected by text scan"
fi
rm -f /tmp/lxc-on-dsm-runtime-boundary.$$

printf '\n'
if [ "$problems" -eq 0 ]; then
    printf 'Result: RUNTIME PACKAGE BOUNDARY PASS'
    [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
    printf '. No install or execution action was performed.\n'
else
    printf 'Result: RUNTIME PACKAGE BOUNDARY BLOCKED: %s PROBLEM(S)' "$problems"
    [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
    printf '. No install or execution action was performed.\n'
    exit 1
fi
