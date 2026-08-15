#!/bin/sh
# Validate a dry-run DSM package payload tree. Does not build or install an SPK.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--payload DIRECTORY]"
}

payload_dir=build/spk-payload/lxc-on-dsm

while [ "$#" -gt 0 ]; do
    case "$1" in
        --payload) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; payload_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

required_files="
INFO
PAYLOAD-MANIFEST.txt
conf/privilege
etc/lab-macvlan.env.example
target/config/lab-macvlan.env.example
scripts/start-stop-status
scripts/preinst
scripts/postinst
scripts/preupgrade
scripts/postupgrade
scripts/preuninst
scripts/postuninst
target/scripts/start-macvlan-profile.sh
target/scripts/stop-macvlan-profile.sh
target/scripts/doctor-macvlan-profile.sh
target/scripts/verify-macvlan-profile.sh
target/scripts/print-lxc-env.sh
target/scripts/prepare-package-access.sh
"

missing=0
printf '%s\n' '# SPK dry-run payload check'
printf '\n'
printf 'payload=%s\n' "$payload_dir"
printf '\n'

[ -d "$payload_dir" ] || { printf 'Missing payload directory: %s\n' "$payload_dir" >&2; exit 1; }

for file in $required_files; do
    if [ -r "${payload_dir}/${file}" ]; then
        printf 'OK: %s\n' "$file"
    else
        printf 'MISSING: %s\n' "$file"
        missing=$((missing + 1))
    fi
done

printf '\n'
if grep -RIn 'silent_install="yes"\|silent_upgrade="yes"\|silent_uninstall="yes"' "$payload_dir" >/tmp/lxc-on-dsm-payload-check.$$ 2>/dev/null; then
    cat /tmp/lxc-on-dsm-payload-check.$$
    rm -f /tmp/lxc-on-dsm-payload-check.$$
    printf '%s\n' 'Result: SPK PAYLOAD BLOCKED. Unsafe package metadata signal found.'
    exit 1
fi
rm -f /tmp/lxc-on-dsm-payload-check.$$

if ! grep -q '/var/packages/${PACKAGE}/etc/lab-macvlan.env' "${payload_dir}/scripts/start-stop-status" &&
   ! grep -q '/var/packages/lxc-on-dsm/etc/lab-macvlan.env' "${payload_dir}/scripts/start-stop-status"; then
    printf '%s\n' 'MISSING: package wrapper does not reference package-owned profile path'
    missing=$((missing + 1))
fi
if ! grep -q '/var/packages/${PACKAGE}/var/artifacts' "${payload_dir}/scripts/start-stop-status" &&
   ! grep -q '/var/packages/lxc-on-dsm/var/artifacts' "${payload_dir}/scripts/start-stop-status"; then
    printf '%s\n' 'MISSING: package wrapper does not reference package-owned artifact path'
    missing=$((missing + 1))
fi
if ! grep -q '"run-as": "package"' "${payload_dir}/conf/privilege"; then
    printf '%s\n' 'MISSING: DSM 7 package privilege run-as declaration'
    missing=$((missing + 1))
fi
if grep -q '"tool"' "${payload_dir}/conf/privilege"; then
    printf '%s\n' 'BLOCKED: package privilege tool attributes are not used in the lab skeleton'
    missing=$((missing + 1))
fi
if ! grep -q 'doctor-macvlan-profile.sh' "${payload_dir}/scripts/start-stop-status"; then
    printf '%s\n' 'MISSING: status wrapper does not call doctor'
    missing=$((missing + 1))
fi
if ! grep -q 'PACKAGE ACCESS PLAN READY' "${payload_dir}/target/scripts/prepare-package-access.sh"; then
    printf '%s\n' 'MISSING: package access script dry-run guard'
    missing=$((missing + 1))
fi
if find "$payload_dir" -name '*.spk' | grep -q .; then
    printf '%s\n' 'BLOCKED: payload contains an .spk artifact'
    missing=$((missing + 1))
fi

printf '\n'
if [ "$missing" -eq 0 ]; then
    printf '%s\n' 'Result: SPK PAYLOAD OK. No .spk was built or installed.'
else
    printf 'Result: SPK PAYLOAD INCOMPLETE: %s issue(s). No .spk was built or installed.\n' "$missing"
    exit 1
fi
