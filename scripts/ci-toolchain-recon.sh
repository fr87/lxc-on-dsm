#!/bin/sh
# CI reconnaissance for the Synology DSM toolchain/build environment.
# Intended for GitHub Actions or another disposable external build runner.
# Does not build LXC and does not touch any DSM host.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--dsm-version VERSION] [--toolkit-version VERSION] [--platform PLATFORM] [--toolchain-file FILE] [--download] [--output DIRECTORY]"
}

dsm_version=7.3-86009
toolkit_version=7.3
platform=apollolake
toolchain_file=apollolake-gcc1220_glibc236_x86_64-GPL.txz
download=0
output_dir=artifacts/ci-toolchain-recon

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dsm-version) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; dsm_version=$2; shift 2 ;;
        --toolkit-version) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolkit_version=$2; shift 2 ;;
        --platform) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; platform=$2; shift 2 ;;
        --toolchain-file) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolchain_file=$2; shift 2 ;;
        --download) download=1; shift ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$dsm_version" in *[!A-Za-z0-9._-]*|'') printf 'Invalid DSM version: %s\n' "$dsm_version" >&2; exit 2 ;; esac
case "$toolkit_version" in *[!A-Za-z0-9._-]*|'') printf 'Invalid toolkit version: %s\n' "$toolkit_version" >&2; exit 2 ;; esac
case "$platform" in *[!A-Za-z0-9._-]*|'') printf 'Invalid platform: %s\n' "$platform" >&2; exit 2 ;; esac
case "$toolchain_file" in *[!A-Za-z0-9._+-]*|'') printf 'Invalid toolchain file: %s\n' "$toolchain_file" >&2; exit 2 ;; esac

stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$output_dir"

toolchain_url="https://archive.synology.com/download/ToolChain/toolchain/${dsm_version}/${toolchain_file}"
toolkit_base_url="https://archive.synology.com/download/ToolChain/toolkit/${toolkit_version}/base_env-${toolkit_version}.txz"
toolkit_dev_url="https://archive.synology.com/download/ToolChain/toolkit/${toolkit_version}/ds.${platform}-${toolkit_version}.dev.txz"
toolkit_env_url="https://archive.synology.com/download/ToolChain/toolkit/${toolkit_version}/ds.${platform}-${toolkit_version}.env.txz"

manifest="${output_dir}/toolchain-recon-${stamp}.env"
report="${output_dir}/toolchain-recon-${stamp}.md"

{
    printf 'generated_utc=%s\n' "$stamp"
    printf 'dsm_version=%s\n' "$dsm_version"
    printf 'toolkit_version=%s\n' "$toolkit_version"
    printf 'platform=%s\n' "$platform"
    printf 'toolchain_file=%s\n' "$toolchain_file"
    printf 'toolchain_url=%s\n' "$toolchain_url"
    printf 'toolkit_base_url=%s\n' "$toolkit_base_url"
    printf 'toolkit_dev_url=%s\n' "$toolkit_dev_url"
    printf 'toolkit_env_url=%s\n' "$toolkit_env_url"
    printf 'download=%s\n' "$download"
} >"$manifest"

{
    printf '%s\n' '# CI Synology toolchain reconnaissance'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'dsm_version=%s\n' "$dsm_version"
    printf 'toolkit_version=%s\n' "$toolkit_version"
    printf 'platform=%s\n' "$platform"
    printf 'toolchain_file=%s\n' "$toolchain_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- CI/build-runner only'
    printf '%s\n' '- does not build LXC'
    printf '%s\n' '- does not install Entware'
    printf '%s\n' '- does not touch any DSM host'
    printf '%s\n' '- does not create runtime bundles'
    printf '\n'
    printf '%s\n' '## URLs'
    printf '\n'
    printf -- '- toolchain: %s\n' "$toolchain_url"
    printf -- '- toolkit base: %s\n' "$toolkit_base_url"
    printf -- '- toolkit dev: %s\n' "$toolkit_dev_url"
    printf -- '- toolkit env: %s\n' "$toolkit_env_url"
} >"$report"

if [ "$download" -eq 1 ]; then
    command -v curl >/dev/null 2>&1 || { printf 'Missing curl for --download\n' >&2; exit 1; }
    download_dir="${output_dir}/downloads"
    mkdir -p "$download_dir"
    for url in "$toolchain_url" "$toolkit_base_url" "$toolkit_dev_url" "$toolkit_env_url"; do
        file="${download_dir}/$(basename "$url")"
        curl -fL "$url" -o "$file"
    done
    if command -v sha256sum >/dev/null 2>&1; then
        ( cd "$download_dir" && sha256sum * ) >"${output_dir}/downloads.sha256"
    fi
    if command -v md5sum >/dev/null 2>&1; then
        ( cd "$download_dir" && md5sum * ) >"${output_dir}/downloads.md5"
    fi
    {
        printf '\n'
        printf '%s\n' '## Downloaded files'
        printf '\n'
        printf '```text\n'
        ls -lh "$download_dir"
        printf '```\n'
        if [ -r "${output_dir}/downloads.sha256" ]; then
            printf '\n'
            printf '%s\n' '## SHA256'
            printf '\n'
            printf '```text\n'
            cat "${output_dir}/downloads.sha256"
            printf '```\n'
        fi
        if [ -r "${output_dir}/downloads.md5" ]; then
            printf '\n'
            printf '%s\n' '## MD5'
            printf '\n'
            printf '```text\n'
            cat "${output_dir}/downloads.md5"
            printf '```\n'
        fi
    } >>"$report"
fi

printf '%s\n' '# CI Synology toolchain reconnaissance'
printf '\n'
printf 'manifest=%s\n' "$manifest"
printf 'report=%s\n' "$report"
printf 'download=%s\n' "$download"
printf '\n'
printf '%s\n' 'Result: CI TOOLCHAIN RECON COMPLETE. No LXC build was performed.'
