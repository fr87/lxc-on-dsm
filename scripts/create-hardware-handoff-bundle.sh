#!/bin/sh
# Create a hardware handoff bundle for the first cautious physical DSM lab run.
# Does not install packages, restore runtime files, start containers or change networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --spk FILE --runtime-bundle FILE [--output DIRECTORY]"
}

spk_file=
runtime_bundle=
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --spk) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; spk_file=$2; shift 2 ;;
        --runtime-bundle) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; runtime_bundle=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$spk_file" ] || { usage >&2; exit 2; }
[ -n "$runtime_bundle" ] || { usage >&2; exit 2; }
[ -r "$spk_file" ] || { printf 'Missing SPK: %s\n' "$spk_file" >&2; exit 1; }
[ -r "$runtime_bundle" ] || { printf 'Missing runtime bundle: %s\n' "$runtime_bundle" >&2; exit 1; }

case "$spk_file" in *.spk) ;; *) printf 'SPK must end with .spk: %s\n' "$spk_file" >&2; exit 1 ;; esac
case "$runtime_bundle" in *.tar.gz|*.tgz) ;; *) printf 'Runtime bundle must end with .tar.gz or .tgz: %s\n' "$runtime_bundle" >&2; exit 1 ;; esac

for required in \
    scripts/analyze-dsm.sh \
    scripts/check-dsm-native-toolchain.sh \
    scripts/compare-reports.sh \
    scripts/evaluate-report.sh \
    scripts/check-lxc-runtime-bundle.sh \
    scripts/check-lxc-runtime-deps.sh \
    scripts/restore-lxc-runtime-bundle.sh \
    scripts/check-package-recovery.sh \
    scripts/create-recovery-bundle.sh \
    scripts/check-recovery-bundle.sh \
    docs/phase9-hardware-lab.md \
    docs/recovery.md \
    docs/safety.md
do
    [ -r "$required" ] || { printf 'Missing required handoff file: %s\n' "$required" >&2; exit 1; }
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
bundle_name="hardware-handoff-lxc-on-dsm-${stamp}"
bundle_dir="${output_dir}/${bundle_name}"
archive_file="${output_dir}/${bundle_name}.tar.gz"

[ ! -e "$bundle_dir" ] || { printf 'Handoff directory already exists: %s\n' "$bundle_dir" >&2; exit 1; }
[ ! -e "$archive_file" ] || { printf 'Handoff archive already exists: %s\n' "$archive_file" >&2; exit 1; }

mkdir -p "$bundle_dir/packages" "$bundle_dir/runtime" "$bundle_dir/scripts" "$bundle_dir/docs" "$bundle_dir/observations"

spk_base=$(basename "$spk_file")
runtime_base=$(basename "$runtime_bundle")

cp "$spk_file" "${bundle_dir}/packages/${spk_base}"
cp "$runtime_bundle" "${bundle_dir}/runtime/${runtime_base}"

for script in \
    analyze-dsm.sh \
    check-dsm-native-toolchain.sh \
    compare-reports.sh \
    evaluate-report.sh \
    check-lxc-runtime-bundle.sh \
    check-lxc-runtime-deps.sh \
    restore-lxc-runtime-bundle.sh \
    check-package-recovery.sh \
    create-recovery-bundle.sh \
    check-recovery-bundle.sh
do
    cp "scripts/${script}" "${bundle_dir}/scripts/${script}"
    chmod 0755 "${bundle_dir}/scripts/${script}"
done

for doc in phase9-hardware-lab.md recovery.md safety.md known-limitations.md compatibility.md; do
    if [ -r "docs/${doc}" ]; then
        cp "docs/${doc}" "${bundle_dir}/docs/${doc}"
    fi
done

{
    printf '%s\n' '# LXC on DSM hardware handoff manifest'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'spk=%s\n' "packages/${spk_base}"
    printf 'runtime_bundle=%s\n' "runtime/${runtime_base}"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '%s\n' '- physical DSM lab handoff only'
    printf '%s\n' '- does not install packages'
    printf '%s\n' '- does not restore runtime files'
    printf '%s\n' '- does not start containers'
    printf '%s\n' '- does not change network settings'
    printf '\n'
    printf '%s\n' '## Suggested first hardware commands'
    printf '%s\n' 'sh scripts/analyze-dsm.sh'
    printf '%s\n' 'sh scripts/check-dsm-native-toolchain.sh'
    printf 'sh scripts/check-lxc-runtime-bundle.sh %s\n' "runtime/${runtime_base}"
    printf 'sh scripts/restore-lxc-runtime-bundle.sh --bundle %s --target /volume1/@lxc/lab/opt\n' "runtime/${runtime_base}"
    printf '%s\n' '# install only after reviewing the dry-run result:'
    printf 'sh scripts/restore-lxc-runtime-bundle.sh --bundle %s --target /volume1/@lxc/lab/opt --install\n' "runtime/${runtime_base}"
    printf '%s\n' '# continue only if this dependency gate passes on the physical NAS:'
    printf '%s\n' 'sh scripts/check-lxc-runtime-deps.sh --prefix /volume1/@lxc/lab/opt'
    printf 'synopkg install %s\n' "packages/${spk_base}"
} >"${bundle_dir}/MANIFEST.txt"

{
    printf '%s\n' '# Handoff file listing'
    printf '\n'
    find "$bundle_dir" -mindepth 1 -print | sort
} >"${bundle_dir}/observations/handoff-files.txt"

if command -v sha256sum >/dev/null 2>&1; then
    (
        cd "$bundle_dir"
        find . -type f ! -name SHA256SUMS -print | sort | xargs sha256sum
    ) >"${bundle_dir}/SHA256SUMS"
fi

tar -czf "$archive_file" -C "$output_dir" "$bundle_name"

printf '%s\n' '# LXC on DSM hardware handoff bundle'
printf '\n'
printf 'bundle_dir=%s\n' "$bundle_dir"
printf 'archive=%s\n' "$archive_file"
printf '\n'
printf '%s\n' 'Result: HARDWARE HANDOFF BUNDLE CREATED. No package, runtime or network state was changed.'
