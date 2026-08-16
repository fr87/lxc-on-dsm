#!/bin/sh
# Validate an LXC runtime bundle archive or directory.
# Does not install files or start containers.
set -eu

usage() {
    printf '%s\n' "Usage: $0 BUNDLE_PATH"
}

[ "$#" -eq 1 ] || { usage >&2; exit 2; }
case "$1" in
    -h|--help) usage; exit 0 ;;
esac

bundle_path=$1
[ -e "$bundle_path" ] || { printf 'Missing bundle path: %s\n' "$bundle_path" >&2; exit 1; }

tmp_dir=
cleanup() {
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ -d "$bundle_path" ]; then
    bundle_dir=$bundle_path
else
    case "$bundle_path" in
        *.tar.gz|*.tgz) ;;
        *) printf 'Bundle archive must end with .tar.gz or .tgz: %s\n' "$bundle_path" >&2; exit 1 ;;
    esac
    tmp_dir=$(mktemp -d)
    tar -xzf "$bundle_path" -C "$tmp_dir"
    bundle_dir=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
    [ -n "$bundle_dir" ] || { printf 'Bundle archive did not contain a top-level directory\n' >&2; exit 1; }
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

has_exec_bit() {
    mode=$(ls -ld "$1" 2>/dev/null | sed 's/ .*//')
    case "$mode" in
        *x*) return 0 ;;
        *) return 1 ;;
    esac
}

required_files="
MANIFEST.txt
runtime/bin/lxc-start
runtime/bin/lxc-info
runtime/bin/lxc-ls
runtime/bin/lxc-stop
runtime/bin/lxc-checkconfig
observations/source-prefix-files.txt
observations/bundled-runtime-files.txt
"

printf '%s\n' '# LXC runtime bundle check'
printf '\n'
printf 'bundle=%s\n' "$bundle_path"
printf 'bundle_dir=%s\n' "$bundle_dir"
printf '\n'
printf '%s\n' '## Required files'
printf '\n'

for file in $required_files; do
    if [ -r "${bundle_dir}/${file}" ]; then
        ok "$file"
    else
        problem "missing required file: $file"
    fi
done

for binary in lxc-start lxc-info lxc-ls lxc-stop lxc-checkconfig; do
    if has_exec_bit "${bundle_dir}/runtime/bin/${binary}"; then
        ok "runtime/bin/${binary} has executable mode bits"
    else
        problem "runtime/bin/${binary} lacks executable mode bits"
    fi
done

if find "${bundle_dir}/runtime" -path '*/containers' -o -path '*/containers/*' -o -path '*/containers/*/rootfs' -o -path '*/containers/*/rootfs/*' | grep -q .; then
    problem "bundle contains container state/rootfs data"
else
    ok "bundle does not contain container state/rootfs data"
fi

if find "$bundle_dir" -name '*.spk' | grep -q .; then
    problem "bundle contains SPK artifact"
else
    ok "bundle does not contain SPK artifacts"
fi

if [ -r "${bundle_dir}/runtime/lib/liblxc.so.1" ] || find "${bundle_dir}/runtime/lib" -name 'liblxc.so*' 2>/dev/null | grep -q .; then
    ok "liblxc is present"
else
    warn "liblxc was not found under runtime/lib"
fi

if [ -r "${bundle_dir}/SHA256SUMS" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        (
            cd "$bundle_dir"
            sha256sum -c SHA256SUMS
        ) >/tmp/lxc-on-dsm-runtime-sha256.$$ 2>&1 && ok "SHA256SUMS verify" || {
            cat /tmp/lxc-on-dsm-runtime-sha256.$$
            problem "SHA256SUMS verification failed"
        }
        rm -f /tmp/lxc-on-dsm-runtime-sha256.$$
    else
        warn "sha256sum command missing; checksum verification skipped"
    fi
else
    warn "SHA256SUMS missing"
fi

printf '\n'
if [ "$problems" -eq 0 ]; then
    printf 'Result: LXC RUNTIME BUNDLE CHECK PASS'
    [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
    printf '. No install action was performed.\n'
else
    printf 'Result: LXC RUNTIME BUNDLE CHECK FOUND %s PROBLEM(S)' "$problems"
    [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
    printf '. No install action was performed.\n'
    exit 1
fi
