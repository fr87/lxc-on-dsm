#!/bin/sh
# Build and validate an experimental SPK that embeds a reviewed CI runtime bundle.
# This script is CI/local packaging only. It does not install packages, restore
# runtime files, start containers or contact any DSM host.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --runtime-artifact-dir DIRECTORY [--image-artifact-dir DIRECTORY] [--output DIRECTORY] [--skip-extracting-runtime-checks]"
}

runtime_artifact_dir=
image_artifact_dir=
output_dir=artifacts/ci-runtime-spk
skip_extracting_runtime_checks=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runtime-artifact-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; runtime_artifact_dir=$2; shift 2 ;;
        --image-artifact-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; image_artifact_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --skip-extracting-runtime-checks) skip_extracting_runtime_checks=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$runtime_artifact_dir" ] || { usage >&2; exit 2; }
[ -d "$runtime_artifact_dir" ] || { printf 'Missing runtime artifact directory: %s\n' "$runtime_artifact_dir" >&2; exit 1; }
[ -n "$image_artifact_dir" ] || image_artifact_dir=$runtime_artifact_dir
[ -d "$image_artifact_dir" ] || { printf 'Missing image artifact directory: %s\n' "$image_artifact_dir" >&2; exit 1; }

mkdir -p "$output_dir"

bundle=$(find "$runtime_artifact_dir" -maxdepth 1 -name 'lxc-runtime-bundle-*.tar.gz' -print | sort | sed -n '1p')
[ -n "$bundle" ] || { printf 'Missing runtime bundle in: %s\n' "$runtime_artifact_dir" >&2; exit 1; }
rootfs_tar=$(find "$image_artifact_dir" -maxdepth 1 -name 'alpine-minirootfs-*.tar.gz' -print | sort | sed -n '1p')

payload_root="${output_dir}/spk-payload"
payload_dir="${payload_root}/lxc-on-dsm"
spk_dir="${output_dir}/spk"
report="${output_dir}/ci-runtime-spk-package.md"

rm -rf "${output_dir}/spk-payload" "$spk_dir"

if [ "$skip_extracting_runtime_checks" -eq 1 ]; then
    {
        printf '%s\n' '# LXC runtime bundle check'
        printf '\n'
        printf 'bundle=%s\n' "$bundle"
        printf '\n'
        printf '%s\n' 'WARN: extracting runtime checks were explicitly skipped.'
        printf '%s\n' 'This is intended only for local Windows/Git-Bash packaging where symlink extraction is unreliable.'
        printf '%s\n' 'Authoritative CI packaging must run without --skip-extracting-runtime-checks.'
    } >"${output_dir}/runtime-bundle-check.txt"
    tar -tzf "$bundle" >"${output_dir}/runtime-bundle-files.txt"
    grep -q 'runtime/bin/lxc-start' "${output_dir}/runtime-bundle-files.txt" || { printf 'Runtime bundle is missing lxc-start\n' >&2; exit 1; }
    grep -q 'runtime/lib' "${output_dir}/runtime-bundle-files.txt" || { printf 'Runtime bundle is missing runtime lib path\n' >&2; exit 1; }
    if grep -q '/containers/\|/containers$' "${output_dir}/runtime-bundle-files.txt"; then
        printf 'Runtime bundle appears to contain container data\n' >&2
        exit 1
    fi
    {
        printf '%s\n' '# Runtime package boundary check'
        printf '\n'
        printf 'path=%s\n' "$bundle"
        printf '\n'
        printf '%s\n' 'WARN: extracting runtime boundary check was explicitly skipped.'
        printf '%s\n' 'Archive listing check found no container data and required runtime paths are present.'
    } >"${output_dir}/runtime-package-boundary.txt"
else
    sh scripts/check-lxc-runtime-bundle.sh "$bundle" >"${output_dir}/runtime-bundle-check.txt"
    sh scripts/check-runtime-package-boundary.sh "$bundle" >"${output_dir}/runtime-package-boundary.txt"
fi
if [ -n "$rootfs_tar" ]; then
    sh scripts/assemble-spk-payload.sh \
        --runtime-bundle "$bundle" \
        --rootfs-tar "$rootfs_tar" \
        --output "$payload_root" >"${output_dir}/assemble-spk-payload.txt"
else
    sh scripts/assemble-spk-payload.sh \
        --runtime-bundle "$bundle" \
        --output "$payload_root" >"${output_dir}/assemble-spk-payload.txt"
fi
sh scripts/check-spk-payload.sh \
    --payload "$payload_dir" >"${output_dir}/check-spk-payload.txt"
sh scripts/build-spk.sh \
    --payload "$payload_dir" \
    --output "$spk_dir" >"${output_dir}/build-spk.txt"

spk=$(find "$spk_dir" -maxdepth 1 -name 'lxc-on-dsm-*.spk' -print | sort | sed -n '1p')
[ -n "$spk" ] || { printf 'SPK was not created in: %s\n' "$spk_dir" >&2; exit 1; }

sh scripts/check-spk-archive.sh --spk "$spk" >"${output_dir}/check-spk-archive.txt"

{
    printf '%s\n' '# CI runtime-bundled SPK package'
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- CI/local packaging only'
    printf '%s\n' '- no DSM host is contacted'
    printf '%s\n' '- no SPK is installed'
    printf '%s\n' '- no runtime bundle is restored'
    printf '%s\n' '- no container is started'
    printf '\n'
    printf '%s\n' '## Inputs and outputs'
    printf '\n'
    printf 'runtime_artifact_dir=%s\n' "$runtime_artifact_dir"
    printf 'image_artifact_dir=%s\n' "$image_artifact_dir"
    printf 'runtime_bundle=%s\n' "$bundle"
    printf 'rootfs_image=%s\n' "${rootfs_tar:-}"
    printf 'skip_extracting_runtime_checks=%s\n' "$skip_extracting_runtime_checks"
    printf 'spk=%s\n' "$spk"
    printf '\n'
    printf '%s\n' '## Validation'
    printf '\n'
    if [ "$skip_extracting_runtime_checks" -eq 1 ]; then
        printf '%s\n' '- runtime bundle extracting checks were skipped by explicit local option'
        printf '%s\n' '- runtime bundle archive listing checks passed'
    else
        printf '%s\n' '- runtime bundle check passed'
        printf '%s\n' '- runtime package boundary check passed'
    fi
    printf '%s\n' '- SPK payload check passed'
    printf '%s\n' '- SPK archive check passed'
} >"$report"

printf '%s\n' '# CI runtime-bundled SPK package'
printf '\n'
printf 'runtime_bundle=%s\n' "$bundle"
printf 'rootfs_image=%s\n' "${rootfs_tar:-}"
printf 'spk=%s\n' "$spk"
printf 'report=%s\n' "$report"
printf 'skip_extracting_runtime_checks=%s\n' "$skip_extracting_runtime_checks"
printf '\n'
printf '%s\n' 'Result: CI RUNTIME-BUNDLED SPK PACKAGE COMPLETE. No DSM host was contacted.'
