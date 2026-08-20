#!/bin/sh
# Prepare a DSM-native CI build workspace for the DS224+/Geminilake target.
# This script runs only on disposable CI/build runners. It never touches DSM.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--output DIRECTORY] [--download] [--extract] [--build-lxc] [--include-base-env] [--discard-work]"
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
build_lxc=0
include_base_env=0
discard_work=0
output_dir=artifacts/ci-dsm-native-runtime-build

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --download) download=1; shift ;;
        --extract) extract=1; download=1; shift ;;
        --build-lxc) build_lxc=1; extract=1; download=1; shift ;;
        --include-base-env) include_base_env=1; shift ;;
        --discard-work) discard_work=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
case "$output_dir" in
    /*) ;;
    *) output_dir="${PWD}/${output_dir}" ;;
esac
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
    printf 'build_lxc=%s\n' "$build_lxc"
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
    if [ "$build_lxc" -eq 1 ]; then
        printf '%s\n' '- creates a runtime bundle but does not test it on DSM'
    else
        printf '%s\n' '- does not create a runtime bundle yet'
    fi
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
    syno_dir="${extract_dir}/synology"
    mkdir -p "$syno_dir"

    if [ "$include_base_env" -eq 1 ]; then
        mkdir -p "${extract_dir}/base"
        tar --no-same-owner --no-same-permissions -xJf "${download_dir}/base_env-${toolkit_version}.txz" -C "${extract_dir}/base"
    fi
    tar --no-same-owner --no-same-permissions -xJf "${download_dir}/${toolchain_file}" -C "$syno_dir"
    chmod -R u+w "$syno_dir" 2>/dev/null || true
    tar --no-same-owner --no-same-permissions -xJf "${download_dir}/ds.${platform}-${toolkit_version}.env.txz" -C "$syno_dir"
    chmod -R u+w "$syno_dir" 2>/dev/null || true
    tar --no-same-owner --no-same-permissions -xJf "${download_dir}/ds.${platform}-${toolkit_version}.dev.txz" -C "$syno_dir"
    chmod -R u+w "$syno_dir" 2>/dev/null || true

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
        find "$syno_dir" -type f \
            \( -name 'x86_64-pc-linux-gnu-gcc' -o -name 'x86_64-pc-linux-gnu-g++' -o -name gcc -o -name g++ \) \
            -print | sort | sed "s#^${extract_dir}/##" | sed -n '1,120p'
        printf '\n'
        printf '%s\n' '## Sysroot candidates'
        find "$syno_dir" -type d \
            \( -path '*/x86_64-pc-linux-gnu/*/sys-root' -o -path '*/usr/local/sysroot' \) \
            -print | sort | sed "s#^${extract_dir}/##" | sed -n '1,120p'
        printf '\n'
        printf '%s\n' '## Target loader candidates'
        find "$syno_dir" -type f -name 'ld-linux-x86-64.so.2' \
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

if [ "$build_lxc" -eq 1 ]; then
    for tool in meson ninja pkg-config gcc g++ make patch curl tar gzip sed awk grep; do
        command -v "$tool" >/dev/null 2>&1 || { printf 'Missing build tool: %s\n' "$tool" >&2; exit 1; }
    done

    cc_path=$(find "$syno_dir" -type f -path '*/usr/local/x86_64-pc-linux-gnu/bin/x86_64-pc-linux-gnu-gcc' | sort | sed -n '1p')
    cxx_path=$(find "$syno_dir" -type f -path '*/usr/local/x86_64-pc-linux-gnu/bin/x86_64-pc-linux-gnu-g++' | sort | sed -n '1p')
    ar_path=$(find "$syno_dir" -type f -path '*/usr/local/x86_64-pc-linux-gnu/bin/x86_64-pc-linux-gnu-ar' | sort | sed -n '1p')
    strip_path=$(find "$syno_dir" -type f -path '*/usr/local/x86_64-pc-linux-gnu/bin/x86_64-pc-linux-gnu-strip' | sort | sed -n '1p')
    sysroot_path=$(find "$syno_dir" -type d -path '*/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root' | sort | sed -n '1p')
    [ -n "$cc_path" ] || { printf 'Missing x86_64-pc-linux-gnu-gcc\n' >&2; exit 1; }
    [ -n "$cxx_path" ] || { printf 'Missing x86_64-pc-linux-gnu-g++\n' >&2; exit 1; }
    [ -n "$ar_path" ] || { printf 'Missing x86_64-pc-linux-gnu-ar\n' >&2; exit 1; }
    [ -n "$strip_path" ] || { printf 'Missing x86_64-pc-linux-gnu-strip\n' >&2; exit 1; }
    [ -n "$sysroot_path" ] || { printf 'Missing Synology sysroot\n' >&2; exit 1; }

    cross_file="${output_dir}/meson-cross-${platform}.txt"
    {
        printf '%s\n' '[binaries]'
        printf "c = '%s'\n" "$cc_path"
        printf "cpp = '%s'\n" "$cxx_path"
        printf "ar = '%s'\n" "$ar_path"
        printf "strip = '%s'\n" "$strip_path"
        printf "pkgconfig = '%s'\n" "$(command -v pkg-config)"
        printf '\n'
        printf '%s\n' '[properties]'
        printf "sys_root = '%s'\n" "$sysroot_path"
        printf "c_args = ['--sysroot=%s']\n" "$sysroot_path"
        printf "cpp_args = ['--sysroot=%s']\n" "$sysroot_path"
        printf "c_link_args = ['--sysroot=%s', '-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2']\n" "$sysroot_path"
        printf "cpp_link_args = ['--sysroot=%s', '-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2']\n" "$sysroot_path"
        printf '\n'
        printf '%s\n' '[host_machine]'
        printf "%s\n" "system = 'linux'"
        printf "%s\n" "cpu_family = 'x86_64'"
        printf "%s\n" "cpu = 'x86_64'"
        printf "%s\n" "endian = 'little'"
    } >"$cross_file"

    build_sources="${work_dir}/sources"
    build_work="${work_dir}/lxc-build"
    destdir="${work_dir}/stage"
    runtime_prefix=/volume1/@lxc/lab/opt
    staged_prefix="${destdir}${runtime_prefix}"

    PKG_CONFIG_SYSROOT_DIR="$sysroot_path"
    PKG_CONFIG_LIBDIR="${sysroot_path}/usr/lib/pkgconfig:${sysroot_path}/usr/share/pkgconfig:${sysroot_path}/usr/lib64/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR

    sh scripts/fetch-sources.sh --output "$build_sources" --gpg-home "${work_dir}/gnupg"
    sh scripts/build-lxc.sh \
        --sources "$build_sources" \
        --build "$build_work" \
        --prefix "$runtime_prefix" \
        --cross-file "$cross_file" \
        --destdir "$destdir" \
        --install

    sh scripts/create-lxc-runtime-bundle.sh \
        --prefix "$staged_prefix" \
        --staged-prefix \
        --output "$output_dir"

    bundle=$(find "$output_dir" -maxdepth 1 -name 'lxc-runtime-bundle-*.tar.gz' -print | sort | sed -n '1p')
    [ -n "$bundle" ] || { printf 'Runtime bundle was not created\n' >&2; exit 1; }
    sh scripts/check-lxc-runtime-bundle.sh "$bundle"
    sh scripts/check-runtime-package-boundary.sh "$bundle"

    {
        printf '\n'
        printf '%s\n' '## LXC runtime build'
        printf '\n'
        printf '```text\n'
        printf 'cross_file=%s\n' "$cross_file"
        printf 'sysroot=%s\n' "$sysroot_path"
        printf 'runtime_prefix=%s\n' "$runtime_prefix"
        printf 'staged_prefix=%s\n' "$staged_prefix"
        printf 'bundle=%s\n' "$bundle"
        printf '```\n'
    } >>"$report"
fi

if [ "$discard_work" -eq 1 ] && [ -n "${work_dir:-}" ]; then
    chmod -R u+w "$work_dir" 2>/dev/null || true
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
printf 'build_lxc=%s\n' "$build_lxc"
printf 'include_base_env=%s\n' "$include_base_env"
printf 'discard_work=%s\n' "$discard_work"
printf '\n'
printf '%s\n' 'Result: DSM-NATIVE RUNTIME CI PREPARATION COMPLETE. No runtime bundle was built.'
