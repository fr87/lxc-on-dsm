#!/bin/sh
# Inspect an experimental DSM SPK archive. Does not install or execute it.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --spk FILE"
}

spk_file=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --spk) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; spk_file=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$spk_file" ] || { usage >&2; exit 2; }
[ -r "$spk_file" ] || { printf 'Missing SPK archive: %s\n' "$spk_file" >&2; exit 1; }
case "$spk_file" in *.spk) ;; *) printf 'Archive does not end with .spk: %s\n' "$spk_file" >&2; exit 1 ;; esac

tmp_dir=$(mktemp -d)
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT HUP INT TERM

tar -tf "$spk_file" | sort >"${tmp_dir}/spk-files.txt"

missing=0
printf '%s\n' '# Experimental SPK archive check'
printf '\n'
printf 'spk=%s\n' "$spk_file"
printf '\n'

for top in INFO conf scripts package.tgz; do
    if grep -qx "$top" "${tmp_dir}/spk-files.txt" || grep -q "^${top}/" "${tmp_dir}/spk-files.txt"; then
        printf 'OK: top-level %s present\n' "$top"
    else
        printf 'MISSING: top-level %s\n' "$top"
        missing=$((missing + 1))
    fi
done

tar -xf "$spk_file" -C "$tmp_dir"
[ -r "${tmp_dir}/INFO" ] || { printf 'MISSING: extracted INFO\n'; missing=$((missing + 1)); }
[ -r "${tmp_dir}/conf/privilege" ] || { printf 'MISSING: extracted conf/privilege\n'; missing=$((missing + 1)); }
[ -r "${tmp_dir}/package.tgz" ] || { printf 'MISSING: extracted package.tgz\n'; missing=$((missing + 1)); }

if [ -r "${tmp_dir}/INFO" ]; then
    grep -q '^package="lxc-on-dsm"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: package metadata name' || { printf '%s\n' 'MISSING: package metadata name'; missing=$((missing + 1)); }
    grep -q '^version="[0-9][0-9.]*-[0-9][0-9]*"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: package metadata version format' || { printf '%s\n' 'MISSING: DSM-compatible numeric package version'; missing=$((missing + 1)); }
    grep -q '^os_min_ver="7\.0-40000"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: package metadata os_min_ver' || { printf '%s\n' 'MISSING: DSM 7 compatible os_min_ver metadata'; missing=$((missing + 1)); }
    grep -q '^silent_install="no"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: silent_install disabled' || { printf '%s\n' 'MISSING: silent_install disabled'; missing=$((missing + 1)); }
    grep -q '^silent_upgrade="no"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: silent_upgrade disabled' || { printf '%s\n' 'MISSING: silent_upgrade disabled'; missing=$((missing + 1)); }
    grep -q '^silent_uninstall="no"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: silent_uninstall disabled' || { printf '%s\n' 'MISSING: silent_uninstall disabled'; missing=$((missing + 1)); }
fi

if [ -r "${tmp_dir}/conf/privilege" ]; then
    grep -q '"run-as": "package"' "${tmp_dir}/conf/privilege" && printf '%s\n' 'OK: package privilege run-as declaration' || { printf '%s\n' 'MISSING: DSM 7 package privilege run-as declaration'; missing=$((missing + 1)); }
    if grep -q '"tool"' "${tmp_dir}/conf/privilege"; then
        printf '%s\n' 'BLOCKED: package privilege tool attributes are not used in the lab skeleton'
        missing=$((missing + 1))
    else
        printf '%s\n' 'OK: package privilege avoids tool attribute rewrites'
    fi
fi

if [ -r "${tmp_dir}/package.tgz" ]; then
    tar -tf "${tmp_dir}/package.tgz" | sort >"${tmp_dir}/package-files.txt"
    mkdir -p "${tmp_dir}/package"
    tar -xzf "${tmp_dir}/package.tgz" -C "${tmp_dir}/package"
    [ -x "${tmp_dir}/package/scripts" ] && printf '%s\n' 'OK: target scripts directory is traversable' || { printf '%s\n' 'MISSING: target scripts directory is not traversable'; missing=$((missing + 1)); }
    [ -x "${tmp_dir}/package/config" ] && printf '%s\n' 'OK: target config directory is traversable' || { printf '%s\n' 'MISSING: target config directory is not traversable'; missing=$((missing + 1)); }
    grep -q 'scripts/start-macvlan-profile.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target start script present' || { printf '%s\n' 'MISSING: target start script'; missing=$((missing + 1)); }
    grep -q 'scripts/stop-macvlan-profile.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target stop script present' || { printf '%s\n' 'MISSING: target stop script'; missing=$((missing + 1)); }
    grep -q 'scripts/doctor-macvlan-profile.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target doctor script present' || { printf '%s\n' 'MISSING: target doctor script'; missing=$((missing + 1)); }
    grep -q 'scripts/prepare-package-access.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target package access script present' || { printf '%s\n' 'MISSING: target package access script'; missing=$((missing + 1)); }
    grep -q 'config/lab-macvlan.env.example' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target profile example present' || { printf '%s\n' 'MISSING: target profile example'; missing=$((missing + 1)); }
    if grep -q 'volume1/@lxc\|lifecycle-state.env\|rootfs' "${tmp_dir}/package-files.txt"; then
        printf '%s\n' 'BLOCKED: archive appears to contain runtime/container data'
        missing=$((missing + 1))
    fi
fi

if [ -r "${tmp_dir}/scripts/start-stop-status" ]; then
    grep -q '/var/packages/${PACKAGE}/var/artifacts' "${tmp_dir}/scripts/start-stop-status" && printf '%s\n' 'OK: wrapper uses package-owned artifact path' || { printf '%s\n' 'MISSING: wrapper package-owned artifact path'; missing=$((missing + 1)); }
fi

if grep -RIn 'silent_install="yes"\|silent_upgrade="yes"\|silent_uninstall="yes"' "$tmp_dir" >/tmp/lxc-on-dsm-archive-check.$$ 2>/dev/null; then
    cat /tmp/lxc-on-dsm-archive-check.$$
    rm -f /tmp/lxc-on-dsm-archive-check.$$
    printf '%s\n' 'BLOCKED: unsafe silent package metadata signal found'
    missing=$((missing + 1))
fi
rm -f /tmp/lxc-on-dsm-archive-check.$$

printf '\n'
if [ "$missing" -eq 0 ]; then
    printf '%s\n' 'Result: SPK ARCHIVE OK. No package was installed and no package scripts were executed.'
else
    printf 'Result: SPK ARCHIVE FAILED: %s issue(s). No package was installed and no package scripts were executed.\n' "$missing"
    exit 1
fi
