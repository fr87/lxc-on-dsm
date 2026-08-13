#!/bin/sh
# Read-only build prerequisite check for Phase 2.
set -eu
PATH="/opt/bin:/opt/sbin:${PATH}"

usage() { printf '%s\n' "Usage: $0 [--manifest FILE]"; }
manifest=manifests/lxc-userspace.env
while [ "$#" -gt 0 ]; do
    case "$1" in
        --manifest) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; manifest=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -r "$manifest" ] || { printf 'Missing manifest: %s\n' "$manifest" >&2; exit 2; }

missing=0
warn=0

check_tool() {
    tool=$1
    level=$2
    label=$3
    if command -v "$tool" >/dev/null 2>&1; then
        printf 'OK: %s (%s)\n' "$label" "$tool"
    elif [ "$level" = required ]; then
        printf 'MISSING: %s (%s)\n' "$label" "$tool"
        missing=$((missing + 1))
    else
        printf 'WARN: %s (%s)\n' "$label" "$tool"
        warn=$((warn + 1))
    fi
}

printf '%s\n' '# DSM LXC Phase 2 prerequisite check'
printf '\n'
printf 'manifest=%s\n' "$manifest"
printf 'architecture=%s\n' "$(uname -m 2>/dev/null || printf unknown)"
printf 'kernel=%s\n' "$(uname -r 2>/dev/null || printf unknown)"
printf '\n'

printf '%s\n' '## Fetch and verification tools'
check_tool curl optional 'HTTP downloader'
check_tool wget optional 'HTTP downloader fallback'
check_tool gpg optional 'GPG signature verifier'
check_tool sha256sum optional 'SHA256 verifier'
check_tool tar required 'tar archive tool'
check_tool gzip required 'gzip archive support'
printf '\n'

printf '%s\n' '## Build tools'
check_tool cc optional 'C compiler'
check_tool gcc optional 'GCC compiler'
check_tool pkg-config required 'pkg-config metadata tool'
check_tool meson required 'Meson build system'
check_tool ninja required 'Ninja build runner'
check_tool make optional 'Make build runner'
check_tool sed required 'sed'
check_tool awk required 'awk'
check_tool grep required 'grep'
printf '\n'

printf '%s\n' '## DSM/Entware signals'
if [ -d /opt ] || [ -d /var/opt ]; then
    printf 'OK: /opt-style prefix exists\n'
else
    printf 'WARN: no /opt-style prefix detected\n'
    warn=$((warn + 1))
fi
check_tool opkg optional 'Entware package manager'
printf '\n'

printf '%s\n' '## Suggested Entware packages'
printf '%s\n' 'opkg update'
printf '%s\n' 'opkg install gcc binutils busybox gawk ldd make sed tar'
printf '%s\n' 'opkg install coreutils-install diffutils ldconfig patch pkg-config --force-overwrite'
printf '%s\n' 'opkg install bash git python3-pip python3-setuptools'
printf '%s\n' 'python3 -m pip install -U wheel meson'
printf '%s\n' 'Build ninja from source if no Entware ninja package is available.'
printf '\n'

if [ "$missing" -gt 0 ]; then
    printf 'Result: BLOCKED for local source builds (%s missing required tool(s), %s warning(s)).\n' "$missing" "$warn"
    exit 1
fi
printf 'Result: READY FOR SOURCE FETCH (%s warning(s)).\n' "$warn"
