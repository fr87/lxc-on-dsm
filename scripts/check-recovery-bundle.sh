#!/bin/sh
# Validate a DSM LXC recovery bundle archive or directory.
# Does not restore files, install packages, start containers or change networking.
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

required_files="
MANIFEST.txt
package/INFO
package/conf/privilege
package/scripts/start-stop-status
package/target/scripts/lxc-on-dsm-root-helper.sh
package/target/scripts/start-macvlan-profile.sh
package/target/scripts/stop-macvlan-profile.sh
package/target/scripts/doctor-macvlan-profile.sh
profile/lab-macvlan.env
observations/package-paths.txt
observations/container-paths.txt
observations/helper-dry-run-status.txt
observations/helper-status.txt
observations/package-recovery-check.txt
"

printf '%s\n' '# DSM LXC recovery bundle check'
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

if find "$bundle_dir" -path '*/rootfs' -o -path '*/rootfs/*' | grep -q .; then
    problem "bundle contains rootfs data"
else
    ok "bundle does not contain rootfs data"
fi

if find "$bundle_dir" -name '*.spk' | grep -q .; then
    problem "bundle contains SPK artifact"
else
    ok "bundle does not contain SPK artifacts"
fi

if [ -r "${bundle_dir}/package/conf/privilege" ]; then
    grep -q '"run-as": "package"' "${bundle_dir}/package/conf/privilege" && ok "privilege declares run-as package" || problem "privilege does not declare run-as package"
    grep -q '"ctrl-script"' "${bundle_dir}/package/conf/privilege" && problem "privilege contains ctrl-script rewrite" || ok "privilege avoids ctrl-script rewrites"
    grep -q '"tool"' "${bundle_dir}/package/conf/privilege" && problem "privilege contains tool rewrite" || ok "privilege avoids tool rewrites"
fi

if [ -r "${bundle_dir}/package/target/scripts/lxc-on-dsm-root-helper.sh" ]; then
    grep -q 'ROOT HELPER DRY RUN COMPLETE' "${bundle_dir}/package/target/scripts/lxc-on-dsm-root-helper.sh" && ok "root helper dry-run guard present" || problem "root helper dry-run guard missing"
fi

if [ -r "${bundle_dir}/observations/helper-dry-run-status.txt" ]; then
    grep -q 'Result: ROOT HELPER DRY RUN COMPLETE' "${bundle_dir}/observations/helper-dry-run-status.txt" && ok "helper dry-run observation passed" || problem "helper dry-run observation did not pass"
fi

if [ -r "${bundle_dir}/observations/helper-status.txt" ]; then
    grep -q 'Result: MACVLAN DOCTOR PASS' "${bundle_dir}/observations/helper-status.txt" && ok "helper status observation passed" || warn "helper status observation did not report PASS"
fi

if [ -r "${bundle_dir}/observations/package-recovery-check.txt" ]; then
    grep -q 'Result: PACKAGE RECOVERY CHECK PASS' "${bundle_dir}/observations/package-recovery-check.txt" && ok "package recovery observation passed" || warn "package recovery observation did not report PASS"
fi

if [ -r "${bundle_dir}/SHA256SUMS" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        (
            cd "$bundle_dir"
            sha256sum -c SHA256SUMS
        ) >/tmp/lxc-on-dsm-bundle-sha256.$$ 2>&1 && ok "SHA256SUMS verify" || {
            cat /tmp/lxc-on-dsm-bundle-sha256.$$
            problem "SHA256SUMS verification failed"
        }
        rm -f /tmp/lxc-on-dsm-bundle-sha256.$$
    else
        warn "sha256sum command missing; checksum verification skipped"
    fi
else
    warn "SHA256SUMS missing"
fi

printf '\n'
if [ "$problems" -eq 0 ]; then
    printf 'Result: RECOVERY BUNDLE CHECK PASS'
    [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
    printf '. No restore action was performed.\n'
else
    printf 'Result: RECOVERY BUNDLE CHECK FOUND %s PROBLEM(S)' "$problems"
    [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
    printf '. No restore action was performed.\n'
    exit 1
fi
