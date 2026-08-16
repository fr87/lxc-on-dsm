#!/bin/sh
# Restore a validated LXC runtime bundle to an empty DSM lab prefix.
# Default mode is dry-run; pass --install to write the target prefix.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --bundle FILE [--target DIRECTORY] [--output DIRECTORY] [--install]"
}

bundle_path=
target_prefix=/volume1/@lxc/lab/opt
output_dir=artifacts
install=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --bundle) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; bundle_path=$2; shift 2 ;;
        --target) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; target_prefix=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --install) install=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$bundle_path" ] || { usage >&2; exit 2; }
[ -e "$bundle_path" ] || { printf 'Missing bundle path: %s\n' "$bundle_path" >&2; exit 1; }

case "$target_prefix" in
    /volume[0-9]*/@lxc/lab/opt) ;;
    *) printf 'Refusing unexpected LXC target prefix: %s\n' "$target_prefix" >&2; exit 2 ;;
esac

tmp_dir=
staging_dir=
cleanup() {
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
    fi
    if [ -n "$staging_dir" ] && [ -d "$staging_dir" ]; then
        rm -rf "$staging_dir"
    fi
}
trap cleanup EXIT HUP INT TERM

tmp_dir=$(mktemp -d)
case "$bundle_path" in
    *.tar.gz|*.tgz) tar -xzf "$bundle_path" -C "$tmp_dir" ;;
    *) printf 'Bundle archive must end with .tar.gz or .tgz: %s\n' "$bundle_path" >&2; exit 1 ;;
esac

bundle_dir=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
[ -n "$bundle_dir" ] || { printf 'Bundle archive did not contain a top-level directory\n' >&2; exit 1; }

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
runtime/lib
observations/source-prefix-files.txt
observations/bundled-runtime-files.txt
"

printf '%s\n' '# LXC runtime bundle restore gate'
printf '\n'
printf 'bundle=%s\n' "$bundle_path"
printf 'bundle_dir=%s\n' "$bundle_dir"
printf 'target_prefix=%s\n' "$target_prefix"
printf 'install=%s\n' "$install"
printf '\n'
printf '%s\n' '## Bundle validation'
printf '\n'

for file in $required_files; do
    if [ -e "${bundle_dir}/${file}" ]; then
        ok "$file"
    else
        problem "missing required bundle path: $file"
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

if [ -r "${bundle_dir}/SHA256SUMS" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        (
            cd "$bundle_dir"
            sha256sum -c SHA256SUMS
        ) >/tmp/lxc-on-dsm-runtime-restore-sha256.$$ 2>&1 && ok "SHA256SUMS verify" || {
            cat /tmp/lxc-on-dsm-runtime-restore-sha256.$$
            problem "SHA256SUMS verification failed"
        }
        rm -f /tmp/lxc-on-dsm-runtime-restore-sha256.$$
    else
        warn "sha256sum command missing; checksum verification skipped"
    fi
else
    warn "SHA256SUMS missing"
fi

printf '\n'
printf '%s\n' '## Target validation'
printf '\n'

target_parent=$(dirname "$target_prefix")
case "$target_parent" in
    /volume[0-9]*/@lxc/lab) ;;
    *) problem "unexpected target parent: $target_parent" ;;
esac

if [ -e "$target_prefix" ]; then
    if [ -d "$target_prefix" ]; then
        if find "$target_prefix" -mindepth 1 -maxdepth 1 -print 2>/dev/null | grep -q .; then
            problem "target prefix already exists and is not empty: $target_prefix"
        else
            ok "target prefix exists and is empty"
        fi
    else
        problem "target prefix exists but is not a directory: $target_prefix"
    fi
else
    ok "target prefix does not exist yet"
fi

if [ "$problems" -ne 0 ]; then
    printf '\n'
    printf 'Result: LXC RUNTIME RESTORE GATE FOUND %s PROBLEM(S)' "$problems"
    [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
    printf '. No runtime files were installed.\n'
    exit 1
fi

if [ "$install" -ne 1 ]; then
    printf '\n'
    printf 'Result: LXC RUNTIME RESTORE DRY RUN PASS'
    [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
    printf '. No runtime files were installed.\n'
    printf 'Install explicitly with: %s --bundle %s --target %s --install\n' "$0" "$bundle_path" "$target_prefix"
    exit 0
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$target_parent" "$output_dir"
staging_dir="${target_parent}/.opt.staging.${stamp}.$$"
[ ! -e "$staging_dir" ] || { printf 'Staging directory already exists: %s\n' "$staging_dir" >&2; exit 1; }
mkdir "$staging_dir"

tar -cf - -C "${bundle_dir}/runtime" . | tar -xf - -C "$staging_dir"

if [ -e "$target_prefix" ]; then
    rmdir "$target_prefix"
fi
mv "$staging_dir" "$target_prefix"
staging_dir=

PATH="${target_prefix}/bin:${target_prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${target_prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

install_report="${output_dir}/lxc-runtime-restore-${stamp}.env"
{
    printf 'generated_utc=%s\n' "$stamp"
    printf 'bundle=%s\n' "$bundle_path"
    printf 'target_prefix=%s\n' "$target_prefix"
    printf 'lxc_start_version=%s\n' "$(lxc-start --version 2>/dev/null || printf unknown)"
    printf 'lxc_info_version=%s\n' "$(lxc-info --version 2>/dev/null || printf unknown)"
} >"$install_report"

printf '\n'
printf '%s\n' '# LXC runtime restore summary'
printf '\n'
printf 'target_prefix=%s\n' "$target_prefix"
printf 'install_report=%s\n' "$install_report"
printf 'lxc_start_version=%s\n' "$(lxc-start --version 2>/dev/null || printf unknown)"
printf '\n'
printf 'Result: LXC RUNTIME RESTORED'
[ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
printf '. No container or network state was changed.\n'
