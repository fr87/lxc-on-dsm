#!/bin/sh
# Read-only reconnaissance for a non-Entware LXC runtime build path.
# Does not install packages, build sources, restore files, start containers or change networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--output DIRECTORY]"
}

output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
report="${output_dir}/dsm-native-toolchain-${stamp}.md"
mkdir -p "$output_dir"

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

tool_path() {
    tool=$1
    if command -v "$tool" >/dev/null 2>&1; then
        command -v "$tool"
    else
        printf '%s\n' missing
    fi
}

capture_cmd() {
    label=$1
    shift
    {
        printf '\n'
        printf '### %s\n' "$label"
        printf '\n'
        printf '```text\n'
        "$@" 2>&1 || true
        printf '```\n'
    } >>"$report"
}

{
    printf '%s\n' '# DSM-native LXC runtime reconnaissance'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'architecture=%s\n' "$(uname -m 2>/dev/null || printf unknown)"
    printf 'kernel=%s\n' "$(uname -r 2>/dev/null || printf unknown)"
    printf 'report=%s\n' "$report"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- read-only'
    printf '%s\n' '- does not install Entware'
    printf '%s\n' '- does not install DSM packages'
    printf '%s\n' '- does not build sources'
    printf '%s\n' '- does not restore runtime files'
    printf '%s\n' '- does not start containers'
    printf '%s\n' '- does not change networking'
    printf '\n'
} >"$report"

printf '%s\n' '# DSM-native LXC runtime reconnaissance'
printf '\n'
printf 'generated_utc=%s\n' "$stamp"
printf 'report=%s\n' "$report"
printf '\n'

printf '%s\n' '## System loader and libc signals'
printf '\n'

system_loader=
for loader in /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2; do
    if [ -x "$loader" ]; then
        system_loader=$loader
        ok "DSM system loader exists: $loader"
        break
    fi
done
[ -n "$system_loader" ] || warn "DSM x86_64 system loader was not observed"

if [ -e /opt/lib/ld-linux-x86-64.so.2 ]; then
    warn "Entware-style /opt loader exists on this host"
else
    ok "Entware-style /opt loader is absent"
fi

if command -v ldd >/dev/null 2>&1; then
    ok "ldd is available: $(command -v ldd)"
else
    warn "ldd is not available"
fi

if command -v file >/dev/null 2>&1; then
    ok "file is available: $(command -v file)"
else
    warn "file is not available"
fi

if command -v readelf >/dev/null 2>&1; then
    ok "readelf is available: $(command -v readelf)"
else
    warn "readelf is not available"
fi

printf '\n'
printf '%s\n' '## Native build tool signals'
printf '\n'

for tool in cc gcc g++ c++ make meson ninja pkg-config pkgconf patch python3 tar gzip xz sed awk grep; do
    path=$(tool_path "$tool")
    if [ "$path" = missing ]; then
        case "$tool" in
            tar|gzip|sed|awk|grep) problem "$tool is missing" ;;
            *) warn "$tool is missing" ;;
        esac
    else
        ok "$tool -> $path"
    fi
done

printf '\n'
printf '%s\n' '## Synology build/toolchain signals'
printf '\n'

synology_signal=0
for path in \
    /usr/local/x86_64-pc-linux-gnu \
    /usr/local/toolkit \
    /usr/local/ds.* \
    /usr/syno/bin \
    /usr/syno/sbin \
    /usr/lib/pkgconfig \
    /usr/local/lib/pkgconfig
do
    # Intentional glob support for the ds.* probe above.
    for expanded in $path; do
        if [ -e "$expanded" ]; then
            ok "observed $expanded"
            synology_signal=1
        fi
    done
done

if [ "$synology_signal" -eq 0 ]; then
    warn "no Synology toolkit-style path observed on this host"
fi

printf '\n'
printf '%s\n' '## Decision hint'
printf '\n'

if [ -n "$system_loader" ]; then
    ok "preferred non-Entware interpreter candidate: $system_loader"
fi

if command -v cc >/dev/null 2>&1 && command -v meson >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1; then
    warn "native build tools are present, but libc/interpreter compatibility still needs a controlled build test"
else
    warn "host does not look ready for an on-device DSM-native source build"
fi

if [ "$synology_signal" -eq 0 ]; then
    warn "likely next path: external Synology-compatible toolchain or relocatable private runtime"
fi

{
    printf '%s\n' '## Tool paths'
    printf '\n'
    for tool in cc gcc g++ c++ make meson ninja pkg-config pkgconf patch python3 tar gzip xz file readelf ldd; do
        printf '%s=%s\n' "$tool" "$(tool_path "$tool")"
    done
} >>"$report"

capture_cmd 'DSM version' cat /etc.defaults/VERSION
capture_cmd 'System loader paths' ls -la /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2 /opt/lib/ld-linux-x86-64.so.2
capture_cmd 'Library search configuration' sh -c 'cat /etc/ld.so.conf 2>/dev/null; ls -la /etc/ld.so.conf.d 2>/dev/null'
capture_cmd 'Synology paths' sh -c 'ls -la /usr/syno /usr/local 2>/dev/null | sed -n "1,120p"'

printf '\n'
if [ "$problems" -eq 0 ]; then
    printf 'Result: DSM-NATIVE TOOLCHAIN RECON COMPLETE'
    [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
    printf '. No system state was changed.\n'
else
    printf 'Result: DSM-NATIVE TOOLCHAIN RECON FOUND %s PROBLEM(S)' "$problems"
    [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
    printf '. No system state was changed.\n'
    exit 1
fi
