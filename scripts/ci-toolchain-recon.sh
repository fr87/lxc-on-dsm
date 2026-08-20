#!/bin/sh
# CI reconnaissance for the Synology DSM toolchain/build environment.
# Intended for GitHub Actions or another disposable external build runner.
# Does not build LXC and does not touch any DSM host.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--dsm-version VERSION] [--toolkit-version VERSION] [--platform PLATFORM] [--toolchain-file FILE] [--download] [--inspect-archives] [--output DIRECTORY]"
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
inspect_archives=0
probe_urls=0
discard_downloads=0
output_dir=artifacts/ci-toolchain-recon

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dsm-version) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; dsm_version=$2; shift 2 ;;
        --toolkit-version) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolkit_version=$2; shift 2 ;;
        --platform) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; platform=$2; shift 2 ;;
        --toolchain-file) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolchain_file=$2; shift 2 ;;
        --toolchain-platform-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolchain_platform_dir=$2; shift 2 ;;
        --toolchain-md5) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolchain_md5=$2; shift 2 ;;
        --toolkit-base-md5) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolkit_base_md5=$2; shift 2 ;;
        --toolkit-dev-md5) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolkit_dev_md5=$2; shift 2 ;;
        --toolkit-env-md5) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; toolkit_env_md5=$2; shift 2 ;;
        --probe-urls) probe_urls=1; shift ;;
        --download) download=1; shift ;;
        --inspect-archives) inspect_archives=1; download=1; shift ;;
        --discard-downloads) discard_downloads=1; shift ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$dsm_version" in *[!A-Za-z0-9._-]*|'') printf 'Invalid DSM version: %s\n' "$dsm_version" >&2; exit 2 ;; esac
case "$toolkit_version" in *[!A-Za-z0-9._-]*|'') printf 'Invalid toolkit version: %s\n' "$toolkit_version" >&2; exit 2 ;; esac
case "$platform" in *[!A-Za-z0-9._-]*|'') printf 'Invalid platform: %s\n' "$platform" >&2; exit 2 ;; esac
case "$toolchain_file" in *[!A-Za-z0-9._+-]*|'') printf 'Invalid toolchain file: %s\n' "$toolchain_file" >&2; exit 2 ;; esac
case "$toolchain_platform_dir" in *[!A-Za-z0-9._%+-]*|'') printf 'Invalid toolchain platform dir: %s\n' "$toolchain_platform_dir" >&2; exit 2 ;; esac
for checksum in "$toolchain_md5" "$toolkit_base_md5" "$toolkit_dev_md5" "$toolkit_env_md5"; do
    case "$checksum" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
        '') ;;
        *) printf 'Invalid MD5 checksum: %s\n' "$checksum" >&2; exit 2 ;;
    esac
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$output_dir"

download_base_url=https://global.synologydownload.com/download
toolchain_url="${download_base_url}/ToolChain/toolchain/${dsm_version}/${toolchain_platform_dir}/${toolchain_file}"
toolkit_base_url="${download_base_url}/ToolChain/toolkit/${toolkit_version}/base/base_env-${toolkit_version}.txz"
toolkit_dev_url="${download_base_url}/ToolChain/toolkit/${toolkit_version}/${platform}/ds.${platform}-${toolkit_version}.dev.txz"
toolkit_env_url="${download_base_url}/ToolChain/toolkit/${toolkit_version}/${platform}/ds.${platform}-${toolkit_version}.env.txz"

manifest="${output_dir}/toolchain-recon-${stamp}.env"
report="${output_dir}/toolchain-recon-${stamp}.md"

{
    printf 'generated_utc=%s\n' "$stamp"
    printf 'dsm_version=%s\n' "$dsm_version"
    printf 'toolkit_version=%s\n' "$toolkit_version"
    printf 'platform=%s\n' "$platform"
    printf 'toolchain_file=%s\n' "$toolchain_file"
    printf 'toolchain_platform_dir=%s\n' "$toolchain_platform_dir"
    printf 'download_base_url=%s\n' "$download_base_url"
    printf 'toolchain_url=%s\n' "$toolchain_url"
    printf 'toolkit_base_url=%s\n' "$toolkit_base_url"
    printf 'toolkit_dev_url=%s\n' "$toolkit_dev_url"
    printf 'toolkit_env_url=%s\n' "$toolkit_env_url"
    printf 'toolchain_md5=%s\n' "$toolchain_md5"
    printf 'toolkit_base_md5=%s\n' "$toolkit_base_md5"
    printf 'toolkit_dev_md5=%s\n' "$toolkit_dev_md5"
    printf 'toolkit_env_md5=%s\n' "$toolkit_env_md5"
    printf 'probe_urls=%s\n' "$probe_urls"
    printf 'download=%s\n' "$download"
    printf 'inspect_archives=%s\n' "$inspect_archives"
    printf 'discard_downloads=%s\n' "$discard_downloads"
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
    printf '%s\n' '- does not extract toolchain archives unless a later build step explicitly does so'
    printf '\n'
    printf '%s\n' '## URLs'
    printf '\n'
    printf -- '- toolchain: %s\n' "$toolchain_url"
    printf -- '- toolkit base: %s\n' "$toolkit_base_url"
    printf -- '- toolkit dev: %s\n' "$toolkit_dev_url"
    printf -- '- toolkit env: %s\n' "$toolkit_env_url"
    printf '\n'
    printf '%s\n' '## Expected MD5 from Synology archive'
    printf '\n'
    printf '```text\n'
    printf '%s  %s\n' "$toolchain_md5" "$toolchain_file"
    printf '%s  %s\n' "$toolkit_base_md5" "base_env-${toolkit_version}.txz"
    printf '%s  %s\n' "$toolkit_dev_md5" "ds.${platform}-${toolkit_version}.dev.txz"
    printf '%s  %s\n' "$toolkit_env_md5" "ds.${platform}-${toolkit_version}.env.txz"
    printf '```\n'
} >"$report"

if [ "$probe_urls" -eq 1 ]; then
    command -v curl >/dev/null 2>&1 || { printf 'Missing curl for --probe-urls\n' >&2; exit 1; }
    probe_file="${output_dir}/url-probe-${stamp}.txt"
    : >"$probe_file"
    for url in "$toolchain_url" "$toolkit_base_url" "$toolkit_dev_url" "$toolkit_env_url"; do
        {
            printf '### %s\n' "$url"
            curl -sSIL --max-time 60 "$url" || printf 'WARN: header probe command failed\n'
            printf '\n'
        } >>"$probe_file" 2>&1
    done
    {
        printf '\n'
        printf '%s\n' '## URL probe'
        printf '\n'
        printf '```text\n'
        cat "$probe_file"
        printf '```\n'
    } >>"$report"
fi

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
        {
            [ -n "$toolchain_md5" ] && printf '%s  %s\n' "$toolchain_md5" "$toolchain_file"
            [ -n "$toolkit_base_md5" ] && printf '%s  %s\n' "$toolkit_base_md5" "base_env-${toolkit_version}.txz"
            [ -n "$toolkit_dev_md5" ] && printf '%s  %s\n' "$toolkit_dev_md5" "ds.${platform}-${toolkit_version}.dev.txz"
            [ -n "$toolkit_env_md5" ] && printf '%s  %s\n' "$toolkit_env_md5" "ds.${platform}-${toolkit_version}.env.txz"
        } >"${output_dir}/expected.md5"
        ( cd "$download_dir" && md5sum -c "../expected.md5" ) >"${output_dir}/expected-md5-check.txt"
    fi
    if [ "$inspect_archives" -eq 1 ]; then
        command -v tar >/dev/null 2>&1 || { printf 'Missing tar for --inspect-archives\n' >&2; exit 1; }
        layout_dir="${output_dir}/archive-layout"
        mkdir -p "$layout_dir"
        focus_file="${output_dir}/build-layout-focus.txt"
        : >"${output_dir}/archive-layout-summary.txt"
        : >"$focus_file"
        {
            printf '%s\n' '# Focused build layout'
            printf '\n'
        } >"$focus_file"
        for file in "$download_dir"/*.txz; do
            base=$(basename "$file")
            sample_file="${layout_dir}/${base}.sample.txt"
            hints_file="${layout_dir}/${base}.hints.txt"
            top_file="${layout_dir}/${base}.top-level.txt"
            tmp_list="${layout_dir}/${base}.full-list.tmp"
            tar -tf "$file" >"$tmp_list"
            sed -n '1,400p' "$tmp_list" >"$sample_file"
            sed 's#^\./##; s#/.*##' "$tmp_list" | sed '/^$/d' | sort -u >"$top_file"
            grep -E '(^|/)(gcc|g\+\+|ld|as|strip|sysroot|libc\.so|ld-linux|pkg-config|pkgconf|cmake|meson|ninja)(/|$|[.-])' "$tmp_list" \
                | sed -n '1,400p' >"$hints_file" || true
            {
                printf '### %s\n' "$base"
                printf 'entries=%s\n' "$(wc -l <"$tmp_list" | tr -d ' ')"
                printf 'top_level=%s\n' "$(tr '\n' ' ' <"$top_file" | sed 's/[ ]*$//')"
                printf 'sample_file=%s\n' "$(basename "$sample_file")"
                printf 'hints_file=%s\n' "$(basename "$hints_file")"
                printf '\n'
            } >>"${output_dir}/archive-layout-summary.txt"
            case "$base" in
                "$toolchain_file")
                    {
                        printf '%s\n' '## Cross compiler archive'
                        printf '\n'
                        grep -E '(^|/)x86_64-pc-linux-gnu-(gcc|g\+\+|cc|c\+\+|ld|ar|ranlib|strip)$|(^|/)bin/(gcc|g\+\+|ld|ar|ranlib|strip)$|sys-root/(lib64|lib|usr/lib)/(ld-linux-x86-64\.so\.2|libc\.so|libc\.so\.6)$' "$tmp_list" \
                            | sed -n '1,240p' || true
                        printf '\n'
                    } >>"$focus_file"
                    ;;
                "ds.${platform}-${toolkit_version}.env.txz")
                    {
                        printf '%s\n' '## Toolkit env archive'
                        printf '\n'
                        grep -E 'usr/local/(sysroot|x86_64-pc-linux-gnu)|sys-root/(lib64|lib|usr/lib)/(ld-linux-x86-64\.so\.2|libc\.so|libc\.so\.6)$|/x86_64-pc-linux-gnu-(gcc|g\+\+|cc|c\+\+|ld|ar|ranlib|strip)$' "$tmp_list" \
                            | sed -n '1,240p' || true
                        printf '\n'
                    } >>"$focus_file"
                    ;;
                "ds.${platform}-${toolkit_version}.dev.txz")
                    {
                        printf '%s\n' '## Toolkit dev archive'
                        printf '\n'
                        grep -E 'usr/local/x86_64-pc-linux-gnu/.*/sys-root/usr/(include|lib|lib64|share/pkgconfig|lib/pkgconfig)|\.(pc|cmake)$' "$tmp_list" \
                            | sed -n '1,240p' || true
                        printf '\n'
                    } >>"$focus_file"
                    ;;
                "base_env-${toolkit_version}.txz")
                    {
                        printf '%s\n' '## Base build environment'
                        printf '\n'
                        grep -E '^usr/bin/(gcc|g\+\+|cc|c\+\+|meson|ninja|pkg-config|pkgconf|cmake|make|python3)$|^usr/lib.*/pkgconfig/.*\.pc$|^usr/share/pkgconfig/.*\.pc$' "$tmp_list" \
                            | sed -n '1,240p' || true
                        printf '\n'
                    } >>"$focus_file"
                    ;;
            esac
            rm -f "$tmp_list"
        done
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
        if [ -r "${output_dir}/expected-md5-check.txt" ]; then
            printf '\n'
            printf '%s\n' '## Expected MD5 verification'
            printf '\n'
            printf '```text\n'
            cat "${output_dir}/expected-md5-check.txt"
            printf '```\n'
        fi
        if [ -r "${output_dir}/archive-layout-summary.txt" ]; then
            printf '\n'
            printf '%s\n' '## Archive layout summary'
            printf '\n'
            printf '```text\n'
            cat "${output_dir}/archive-layout-summary.txt"
            printf '```\n'
        fi
        if [ -r "${output_dir}/build-layout-focus.txt" ]; then
            printf '\n'
            printf '%s\n' '## Focused build layout'
            printf '\n'
            printf '```text\n'
            cat "${output_dir}/build-layout-focus.txt"
            printf '```\n'
        fi
    } >>"$report"
    if [ "$discard_downloads" -eq 1 ]; then
        rm -rf "$download_dir"
        printf 'downloads_discarded=1\n' >>"$manifest"
        {
            printf '\n'
            printf '%s\n' '## Download retention'
            printf '\n'
            printf '%s\n' 'Downloaded tarballs were discarded after checksum verification.'
        } >>"$report"
    else
        printf 'downloads_discarded=0\n' >>"$manifest"
    fi
fi

printf '%s\n' '# CI Synology toolchain reconnaissance'
printf '\n'
printf 'manifest=%s\n' "$manifest"
printf 'report=%s\n' "$report"
printf 'probe_urls=%s\n' "$probe_urls"
printf 'download=%s\n' "$download"
printf 'inspect_archives=%s\n' "$inspect_archives"
printf 'discard_downloads=%s\n' "$discard_downloads"
printf '\n'
printf '%s\n' 'Result: CI TOOLCHAIN RECON COMPLETE. No LXC build was performed.'
