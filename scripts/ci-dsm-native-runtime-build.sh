#!/bin/sh
# Prepare a DSM-native CI build workspace for the DS224+/Geminilake target.
# This script runs only on disposable CI/build runners. It never touches DSM.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--output DIRECTORY] [--download] [--extract] [--include-base-env] [--discard-work]"
}

dsm_version=7.3-86009
toolkit_version=7.3
platform=geminilake
toolchain_file=geminilake-gcc1220_glibc236_x86_64-GPL.txz
toolchain_platform_dir='Intel%20x86%20Linux%204.4.302%20%28GeminiLake%29'
toolchain_md5=bc93d88359a055b398d8e78965bc95cc
toolkit_base_md5=fd0862fa44189606bd64cc32138f3302
toolkit_dev_md5=cb6221764494afdbec7aa1a22ea3ad6a
toolkit_env_md5=ec544e4e943da80f8b18163516c4ba46
download=0
extract=0
include_base_env=0
discard_work=0
output_dir=artifacts/ci-dsm-native-runtime-build

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --download) download=1; shift ;;
        --extract) extract=1; download=1; shift ;;
        --include-base-env) include_base_env=1; shift ;;
        --discard-work) discard_work=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$output_dir"

download_base_url=https://global.synologydownload.com/download
toolchain_url="${download_base_url}/ToolChain/toolchain/${dsm_version}/${toolchain_platform_dir}/${toolchain_file}"
toolkit_base_url="${download_base_url}/ToolChain/toolkit/${toolkit_version}/base/base_env-${toolkit_version}.txz"
toolkit_dev_url="${download_base_url}/ToolChain/toolkit/${toolkit_version}/${platform}/ds.${platform}-${toolkit_version}.dev.txz"
toolkit_env_url="${download_base_url}/ToolChain/toolkit/${toolkit_version}/${platform}/ds.${platform}-${toolkit_version}.env.txz"

manifest="${output_dir}/dsm-native-runtime-build-${stamp}.env"
report="${output_dir}/dsm-native-runtime-build-${stamp}.md"

{
    printf 'generated_utc=%s\n' "$stamp"
    printf 'dsm_version=%s\n' "$dsm_version"
    printf 'toolkit_version=%s\n' "$toolkit_version"
    printf 'platform=%s\n' "$platform"
    printf 'toolchain_file=%s\n' "$toolchain_file"
    printf 'download=%s\n' "$download"
    printf 'extract=%s\n' "$extract"
    printf 'include_base_env=%s\n' "$include_base_env"
    printf 'discard_work=%s\n' "$discard_work"
    printf 'toolchain_url=%s\n' "$toolchain_url"
    printf 'toolkit_base_url=%s\n' "$toolkit_base_url"
    printf 'toolkit_dev_url=%s\n' "$toolkit_dev_url"
    printf 'toolkit_env_url=%s\n' "$toolkit_env_url"
} >"$manifest"

{
    printf '%s\n' '# DSM-native runtime CI build preparation'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'platform=%s\n' "$platform"
    printf 'dsm_version=%s\n' "$dsm_version"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- CI/build-runner only'
    printf '%s\n' '- does not touch any DSM host'
    printf '%s\n' '- does not install Entware'
    printf '%s\n' '- does not start containers'
    printf '%s\n' '- does not create a runtime bundle yet'
    printf '%s\n' '- skips Synology base_env unless explicitly requested'
} >"$report"

if [ "$download" -eq 1 ]; then
    command -v curl >/dev/null 2>&1 || { printf 'Missing curl\n' >&2; exit 1; }
    command -v md5sum >/dev/null 2>&1 || { printf 'Missing md5sum\n' >&2; exit 1; }
    work_dir="${output_dir}/work"
    download_dir="${work_dir}/downloads"
    mkdir -p "$download_dir"

    for url in "$toolchain_url" "$toolkit_dev_url" "$toolkit_env_url"; do
        curl -fL "$url" -o "${download_dir}/$(basename "$url")"
    done
    if [ "$include_base_env" -eq 1 ]; then
        curl -fL "$toolkit_base_url" -o "${download_dir}/base_env-${toolkit_version}.txz"
    fi

    {
        printf '%s  %s\n' "$toolchain_md5" "$toolchain_file"
        printf '%s  %s\n' "$toolkit_dev_md5" "ds.${platform}-${toolkit_version}.dev.txz"
        printf '%s  %s\n' "$toolkit_env_md5" "ds.${platform}-${toolkit_version}.env.txz"
        if [ "$include_base_env" -eq 1 ]; then
            printf '%s  %s\n' "$toolkit_base_md5" "base_env-${toolkit_version}.txz"
        fi
    } >"${output_dir}/expected.md5"
    ( cd "$download_dir" && md5sum -c "../../expected.md5" ) >"${output_dir}/expected-md5-check.txt"

    {
        printf '\n'
        printf '%s\n' '## Download verification'
        printf '\n'
        printf '```text\n'
        cat "${output_dir}/expected-md5-check.txt"
        printf '```\n'
    } >>"$report"
fi

if [ "$extract" -eq 1 ]; then
    command -v tar >/dev/null 2>&1 || { printf 'Missing tar\n' >&2; exit 1; }
    extract_dir="${work_dir}/extract"
    mkdir -p "${extract_dir}/toolchain" "${extract_dir}/env" "${extract_dir}/dev"

    if [ "$include_base_env" -eq 1 ]; then
        mkdir -p "${extract_dir}/base"
        tar -xJf "${download_dir}/base_env-${toolkit_version}.txz" -C "${extract_dir}/base"
    fi
    tar -xJf "${download_dir}/${toolchain_file}" -C "${extract_dir}/toolchain"
    tar -xJf "${download_dir}/ds.${platform}-${toolkit_version}.env.txz" -C "${extract_dir}/env"
    tar -xJf "${download_dir}/ds.${platform}-${toolkit_version}.dev.txz" -C "${extract_dir}/dev"

    {
        printf '%s\n' '# Toolchain path candidates'
        printf '\n'
        printf '%s\n' '## CI host build tools'
        for tool in meson ninja pkg-config cmake make python3 gcc g++; do
            if command -v "$tool" >/dev/null 2>&1; then
                printf 'OK: %s -> %s\n' "$tool" "$(command -v "$tool")"
            else
                printf 'MISS: %s\n' "$tool"
            fi
        done
        if [ "$include_base_env" -eq 1 ]; then
            printf '\n'
            printf '%s\n' '## Synology base_env build tools'
            for tool in meson ninja pkg-config cmake make python3 gcc g++; do
                if [ -x "${extract_dir}/base/usr/bin/${tool}" ]; then
                    printf 'OK: %s -> %s\n' "$tool" "base/usr/bin/${tool}"
                else
                    printf 'MISS: %s\n' "$tool"
                fi
            done
        fi
        printf '\n'
        printf '%s\n' '## Cross compiler candidates'
        find "${extract_dir}/toolchain" "${extract_dir}/env" -type f \
            \( -name 'x86_64-pc-linux-gnu-gcc' -o -name 'x86_64-pc-linux-gnu-g++' -o -name gcc -o -name g++ \) \
            -print | sort | sed "s#^${extract_dir}/##" | sed -n '1,120p'
        printf '\n'
        printf '%s\n' '## Sysroot candidates'
        find "${extract_dir}/env" "${extract_dir}/dev" -type d \
            \( -path '*/x86_64-pc-linux-gnu/*/sys-root' -o -path '*/usr/local/sysroot' \) \
            -print | sort | sed "s#^${extract_dir}/##" | sed -n '1,120p'
        printf '\n'
        printf '%s\n' '## Target loader candidates'
        find "${extract_dir}/env" "${extract_dir}/dev" -type f -name 'ld-linux-x86-64.so.2' \
            -print | sort | sed "s#^${extract_dir}/##" | sed -n '1,120p'
    } >"${output_dir}/toolchain-path-candidates.txt"

    {
        printf '\n'
        printf '%s\n' '## Extracted path candidates'
        printf '\n'
        printf '```text\n'
        cat "${output_dir}/toolchain-path-candidates.txt"
        printf '```\n'
    } >>"$report"
fi

if [ "$discard_work" -eq 1 ] && [ -n "${work_dir:-}" ]; then
    rm -rf "$work_dir"
    printf 'work_discarded=1\n' >>"$manifest"
    {
        printf '\n'
        printf '%s\n' '## Work retention'
        printf '\n'
        printf '%s\n' 'Downloaded and extracted build-only files were discarded before artifact upload.'
    } >>"$report"
else
    printf 'work_discarded=0\n' >>"$manifest"
fi

printf '%s\n' '# DSM-native runtime CI build preparation'
printf '\n'
printf 'manifest=%s\n' "$manifest"
printf 'report=%s\n' "$report"
printf 'download=%s\n' "$download"
printf 'extract=%s\n' "$extract"
printf 'include_base_env=%s\n' "$include_base_env"
printf 'discard_work=%s\n' "$discard_work"
printf '\n'
printf '%s\n' 'Result: DSM-NATIVE RUNTIME CI PREPARATION COMPLETE. No runtime bundle was built.'
