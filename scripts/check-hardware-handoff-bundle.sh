#!/bin/sh
# Validate a hardware handoff bundle. Does not install, restore or start anything.
set -eu

usage() {
    printf '%s\n' "Usage: $0 BUNDLE_PATH"
}

[ "$#" -eq 1 ] || { usage >&2; exit 2; }
case "$1" in
    -h|--help) usage; exit 0 ;;
esac

bundle_path=$1
[ -e "$bundle_path" ] || { printf 'Missing handoff bundle: %s\n' "$bundle_path" >&2; exit 1; }

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
        *) printf 'Handoff bundle must end with .tar.gz or .tgz: %s\n' "$bundle_path" >&2; exit 1 ;;
    esac
    tmp_dir=$(mktemp -d)
    tar -xzf "$bundle_path" -C "$tmp_dir"
    bundle_dir=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
    [ -n "$bundle_dir" ] || { printf 'Handoff archive did not contain a top-level directory\n' >&2; exit 1; }
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

required_files="
MANIFEST.txt
scripts/analyze-dsm.sh
scripts/check-dsm-native-toolchain.sh
scripts/compare-reports.sh
scripts/evaluate-report.sh
scripts/check-lxc-runtime-bundle.sh
scripts/check-lxc-runtime-deps.sh
scripts/check-runtime-package-boundary.sh
scripts/restore-lxc-runtime-bundle.sh
scripts/check-package-recovery.sh
scripts/create-recovery-bundle.sh
scripts/check-recovery-bundle.sh
docs/phase9-hardware-lab.md
docs/recovery.md
docs/safety.md
observations/handoff-files.txt
"

printf '%s\n' '# LXC on DSM hardware handoff bundle check'
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

spk_count=$(find "${bundle_dir}/packages" -maxdepth 1 -type f -name '*.spk' 2>/dev/null | wc -l | tr -d ' ')
runtime_count=$(find "${bundle_dir}/runtime" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' \) 2>/dev/null | wc -l | tr -d ' ')

if [ "$spk_count" = 1 ]; then
    ok "exactly one SPK is present"
else
    problem "expected exactly one SPK, found ${spk_count}"
fi

if [ "$runtime_count" = 1 ]; then
    ok "exactly one runtime bundle is present"
else
    problem "expected exactly one runtime bundle, found ${runtime_count}"
fi

runtime_bundle=$(find "${bundle_dir}/runtime" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' \) 2>/dev/null | sed -n '1p')
if [ -n "$runtime_bundle" ]; then
    if tar -tzf "$runtime_bundle" >/tmp/lxc-on-dsm-handoff-runtime-list.$$ 2>/tmp/lxc-on-dsm-handoff-runtime-tar.$$; then
        grep -q '/runtime/bin/lxc-start$' /tmp/lxc-on-dsm-handoff-runtime-list.$$ && ok "runtime bundle contains lxc-start" || problem "runtime bundle missing lxc-start"
        grep -q '/runtime/bin/lxc-stop$' /tmp/lxc-on-dsm-handoff-runtime-list.$$ && ok "runtime bundle contains lxc-stop" || problem "runtime bundle missing lxc-stop"
        grep -q '/runtime/lib/' /tmp/lxc-on-dsm-handoff-runtime-list.$$ && ok "runtime bundle contains lib directory" || warn "runtime bundle lib directory not observed"
        if grep -q '/runtime/.*/containers/' /tmp/lxc-on-dsm-handoff-runtime-list.$$; then
            problem "runtime bundle appears to contain container state"
        else
            ok "runtime bundle does not list container state"
        fi
    else
        cat /tmp/lxc-on-dsm-handoff-runtime-tar.$$
        problem "runtime bundle could not be listed"
    fi
    rm -f /tmp/lxc-on-dsm-handoff-runtime-list.$$ /tmp/lxc-on-dsm-handoff-runtime-tar.$$
fi

if [ -r "${bundle_dir}/MANIFEST.txt" ]; then
    grep -q 'restore-lxc-runtime-bundle.sh --bundle' "${bundle_dir}/MANIFEST.txt" && ok "manifest includes runtime restore command" || problem "manifest missing runtime restore command"
    grep -q 'check-lxc-runtime-deps.sh --prefix' "${bundle_dir}/MANIFEST.txt" && ok "manifest includes runtime dependency gate command" || problem "manifest missing runtime dependency gate command"
    grep -q 'check-runtime-package-boundary.sh' "${bundle_dir}/MANIFEST.txt" && ok "manifest includes runtime package boundary command" || problem "manifest missing runtime package boundary command"
    grep -q 'synopkg install' "${bundle_dir}/MANIFEST.txt" && ok "manifest includes SPK install command" || problem "manifest missing SPK install command"
fi

if find "$bundle_dir" -path '*/containers' -o -path '*/containers/*' | grep -q .; then
    problem "handoff bundle contains container state directory"
else
    ok "handoff bundle does not contain container state directories"
fi

if [ -r "${bundle_dir}/SHA256SUMS" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        (
            cd "$bundle_dir"
            sha256sum -c SHA256SUMS
        ) >/tmp/lxc-on-dsm-handoff-sha256.$$ 2>&1 && ok "SHA256SUMS verify" || {
            cat /tmp/lxc-on-dsm-handoff-sha256.$$
            problem "SHA256SUMS verification failed"
        }
        rm -f /tmp/lxc-on-dsm-handoff-sha256.$$
    else
        warn "sha256sum command missing; checksum verification skipped"
    fi
else
    warn "SHA256SUMS missing"
fi

printf '\n'
if [ "$problems" -eq 0 ]; then
    printf 'Result: HARDWARE HANDOFF BUNDLE CHECK PASS'
    [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
    printf '. No install or restore action was performed.\n'
else
    printf 'Result: HARDWARE HANDOFF BUNDLE CHECK FOUND %s PROBLEM(S)' "$problems"
    [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
    printf '. No install or restore action was performed.\n'
    exit 1
fi
