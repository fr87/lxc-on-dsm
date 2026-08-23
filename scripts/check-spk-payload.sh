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
target/scripts/restore-lxc-runtime-bundle.sh
target/scripts/check-lxc-runtime-deps.sh
target/scripts/install-packaged-runtime.sh
target/scripts/create-packaged-container.sh
target/scripts/run-packaged-smoke-test.sh
target/scripts/run-packaged-macvlan-dhcp-test.sh
target/scripts/lxc-on-dsm-root-helper.sh
target/ui/config
target/ui/index.html
target/ui/style.css
target/ui/app.js
target/ui/status.json
target/ui/images/icon_16.png
target/ui/images/icon_24.png
target/ui/images/icon_32.png
target/ui/images/icon_48.png
target/ui/images/icon_64.png
target/ui/images/icon_72.png
target/ui/images/icon_256.png
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
    printf '%s\n' 'MISSING: DSM 7 package run-as declaration'
    missing=$((missing + 1))
fi
if ! grep -q '^dsmuidir="ui"$' "${payload_dir}/INFO"; then
    printf '%s\n' 'MISSING: DSM UI directory metadata'
    missing=$((missing + 1))
fi
if ! grep -q '^dsmappname="com\.fr87\.LxcOnDsmLab"$' "${payload_dir}/INFO"; then
    printf '%s\n' 'MISSING: DSM app name metadata'
    missing=$((missing + 1))
fi
if ! grep -q '"url": "3rdparty/lxc-on-dsm/index.html"' "${payload_dir}/target/ui/config"; then
    printf '%s\n' 'MISSING: DSM UI local URL config'
    missing=$((missing + 1))
fi
if ! grep -q '"icon": "images/icon_{0}.png"' "${payload_dir}/target/ui/config"; then
    printf '%s\n' 'MISSING: DSM UI icon config'
    missing=$((missing + 1))
fi
if ! grep -q 'Package Center start/stop is intentionally blocked' "${payload_dir}/target/ui/index.html"; then
    printf '%s\n' 'MISSING: DSM UI root lifecycle warning'
    missing=$((missing + 1))
fi
if ! grep -q '"runtime_bundle_packaged":' "${payload_dir}/target/ui/status.json"; then
    printf '%s\n' 'MISSING: DSM UI runtime bundle status'
    missing=$((missing + 1))
fi
if grep -q '"ctrl-script"' "${payload_dir}/conf/privilege"; then
    printf '%s\n' 'BLOCKED: package ctrl-script attributes are not used in the lab skeleton'
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
if ! grep -q 'requires root on DSM' "${payload_dir}/scripts/start-stop-status"; then
    printf '%s\n' 'MISSING: start/stop wrapper does not explain root lifecycle gate'
    missing=$((missing + 1))
fi
if ! grep -q 'lxc-on-dsm-root-helper.sh' "${payload_dir}/scripts/start-stop-status"; then
    printf '%s\n' 'MISSING: start/stop wrapper does not point to installed root helper'
    missing=$((missing + 1))
fi
if ! grep -q 'ROOT HELPER DRY RUN COMPLETE' "${payload_dir}/target/scripts/lxc-on-dsm-root-helper.sh"; then
    printf '%s\n' 'MISSING: installed helper dry-run guard'
    missing=$((missing + 1))
fi
helper_mode=$(ls -l "${payload_dir}/target/scripts/lxc-on-dsm-root-helper.sh" 2>/dev/null | awk '{ print $1 }' | sed -n '1p')
case "$helper_mode" in
    -rwxr-xr-x) printf '%s\n' 'OK: installed helper is executable without setuid' ;;
    *s*) printf 'BLOCKED: installed helper appears to have setuid/setgid mode: %s\n' "$helper_mode"; missing=$((missing + 1)) ;;
    *) printf 'BLOCKED: installed helper has unexpected mode: %s\n' "$helper_mode"; missing=$((missing + 1)) ;;
esac
if ! grep -q 'PACKAGE ACCESS PLAN READY' "${payload_dir}/target/scripts/prepare-package-access.sh"; then
    printf '%s\n' 'MISSING: package access script dry-run guard'
    missing=$((missing + 1))
fi
if ! grep -q 'LXC RUNTIME RESTORE DRY RUN PASS' "${payload_dir}/target/scripts/restore-lxc-runtime-bundle.sh"; then
    printf '%s\n' 'MISSING: packaged runtime restore script dry-run gate'
    missing=$((missing + 1))
fi
if ! grep -q 'No container was started' "${payload_dir}/target/scripts/check-lxc-runtime-deps.sh"; then
    printf '%s\n' 'MISSING: packaged runtime dependency check no-container guarantee'
    missing=$((missing + 1))
fi
if ! grep -q 'Packaged LXC runtime restore' "${payload_dir}/target/scripts/install-packaged-runtime.sh"; then
    printf '%s\n' 'MISSING: packaged runtime install wrapper'
    missing=$((missing + 1))
fi
if ! grep -q -- '--install' "${payload_dir}/target/scripts/install-packaged-runtime.sh"; then
    printf '%s\n' 'MISSING: packaged runtime install wrapper explicit install gate'
    missing=$((missing + 1))
fi
if ! grep -q 'PACKAGED CONTAINER CREATE DRY RUN COMPLETE' "${payload_dir}/target/scripts/create-packaged-container.sh"; then
    printf '%s\n' 'MISSING: packaged container create dry-run gate'
    missing=$((missing + 1))
fi
if ! grep -q 'No container was started' "${payload_dir}/target/scripts/create-packaged-container.sh"; then
    printf '%s\n' 'MISSING: packaged container create no-start guarantee'
    missing=$((missing + 1))
fi
if ! grep -q 'PACKAGED SMOKE TEST PASSED' "${payload_dir}/target/scripts/run-packaged-smoke-test.sh"; then
    printf '%s\n' 'MISSING: packaged smoke test success marker'
    missing=$((missing + 1))
fi
if ! grep -q 'lxc.net.0.type = none' "${payload_dir}/target/scripts/run-packaged-smoke-test.sh"; then
    printf '%s\n' 'MISSING: packaged smoke test networkless guard'
    missing=$((missing + 1))
fi
if ! grep -q 'PACKAGED MACVLAN DHCP TEST DRY RUN COMPLETE' "${payload_dir}/target/scripts/run-packaged-macvlan-dhcp-test.sh"; then
    printf '%s\n' 'MISSING: packaged macvlan DHCP dry-run gate'
    missing=$((missing + 1))
fi
if ! grep -q 'lxc.net.0.type = macvlan' "${payload_dir}/target/scripts/run-packaged-macvlan-dhcp-test.sh"; then
    printf '%s\n' 'MISSING: packaged macvlan DHCP config guard'
    missing=$((missing + 1))
fi
if ! grep -q '0730' "${payload_dir}/target/scripts/prepare-package-access.sh"; then
    printf '%s\n' 'MISSING: package access script lifecycle-state write permission'
    missing=$((missing + 1))
fi
if ! grep -q -- '--logfile' "${payload_dir}/target/scripts/start-macvlan-profile.sh"; then
    printf '%s\n' 'MISSING: start script LXC debug logfile capture'
    missing=$((missing + 1))
fi
if find "$payload_dir" -name '*.spk' | grep -q .; then
    printf '%s\n' 'BLOCKED: payload contains an .spk artifact'
    missing=$((missing + 1))
fi
if [ -e "${payload_dir}/target/runtime/lxc-runtime-bundle.tar.gz" ]; then
    printf '%s\n' 'OK: packaged runtime bundle is present'
    if [ -r "${payload_dir}/target/runtime/README.md" ]; then
        printf '%s\n' 'OK: packaged runtime bundle manifest is present'
    else
        printf '%s\n' 'MISSING: packaged runtime bundle manifest'
        missing=$((missing + 1))
    fi
    if ! grep -q 'does not restore it automatically' "${payload_dir}/target/runtime/README.md"; then
        printf '%s\n' 'MISSING: packaged runtime manifest does not document no-autorestore behavior'
        missing=$((missing + 1))
    fi
    if tar -tzf "${payload_dir}/target/runtime/lxc-runtime-bundle.tar.gz" >/tmp/lxc-on-dsm-packaged-runtime-list.$$ 2>/tmp/lxc-on-dsm-packaged-runtime-tar.$$; then
        if grep -q '/containers/\|/containers$' /tmp/lxc-on-dsm-packaged-runtime-list.$$; then
            printf '%s\n' 'BLOCKED: packaged runtime bundle appears to contain container/rootfs data'
            missing=$((missing + 1))
        else
            printf '%s\n' 'OK: packaged runtime bundle listing has no container data'
        fi
        if grep -q '/build/work/\|/build/sources/\|build.ninja\|meson-private\|meson-info' /tmp/lxc-on-dsm-packaged-runtime-list.$$; then
            printf '%s\n' 'BLOCKED: packaged runtime bundle appears to contain build intermediates'
            missing=$((missing + 1))
        else
            printf '%s\n' 'OK: packaged runtime bundle listing has no build intermediates'
        fi
    else
        cat /tmp/lxc-on-dsm-packaged-runtime-tar.$$
        printf '%s\n' 'BLOCKED: packaged runtime bundle could not be listed'
        missing=$((missing + 1))
    fi
    rm -f /tmp/lxc-on-dsm-packaged-runtime-list.$$ /tmp/lxc-on-dsm-packaged-runtime-tar.$$
else
    printf '%s\n' 'WARN: no runtime bundle packaged; SPK is management-only'
fi
if [ -e "${payload_dir}/target/images/alpine-minirootfs.tar.gz" ]; then
    printf '%s\n' 'OK: packaged Alpine image is present'
    if [ -r "${payload_dir}/target/images/README.md" ]; then
        printf '%s\n' 'OK: packaged Alpine image manifest is present'
    else
        printf '%s\n' 'MISSING: packaged Alpine image manifest'
        missing=$((missing + 1))
    fi
    if ! grep -q 'does not extract it automatically' "${payload_dir}/target/images/README.md"; then
        printf '%s\n' 'MISSING: packaged Alpine image manifest does not document no-autoextract behavior'
        missing=$((missing + 1))
    fi
else
    printf '%s\n' 'WARN: no Alpine image packaged; container creation requires an external image'
fi

printf '\n'
if [ "$missing" -eq 0 ]; then
    printf '%s\n' 'Result: SPK PAYLOAD OK. No .spk was built or installed.'
else
    printf 'Result: SPK PAYLOAD INCOMPLETE: %s issue(s). No .spk was built or installed.\n' "$missing"
    exit 1
fi
