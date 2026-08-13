#!/bin/sh
set -eu
target=scripts/analyze-dsm.sh
for script in scripts/analyze-dsm.sh scripts/compare-reports.sh scripts/evaluate-report.sh scripts/check-phase2-prereqs.sh scripts/fetch-sources.sh scripts/build-lxc.sh scripts/build-pkgconf.sh scripts/verify-lxc-install.sh scripts/verify-lxc-runtime.sh scripts/print-lxc-env.sh scripts/plan-entware-bootstrap.sh scripts/create-lab-container.sh; do
    sh -n "$script"
done
forbidden='(^|[[:space:]])(mount|umount|modprobe|insmod|rmmod|sysctl[[:space:]]+-w|apk[[:space:]]+(add|del)|apt[[:space:]]+(install|remove|purge)|opkg[[:space:]]+(install|remove|upgrade)|synopkg|iptables[[:space:]]+-|nft[[:space:]]+(add|delete|flush))([[:space:]]|$)'
if grep -En "$forbidden" scripts/analyze-dsm.sh scripts/compare-reports.sh scripts/evaluate-report.sh scripts/check-phase2-prereqs.sh scripts/fetch-sources.sh scripts/build-lxc.sh scripts/build-pkgconf.sh scripts/verify-lxc-install.sh scripts/verify-lxc-runtime.sh scripts/print-lxc-env.sh; then
    printf '%s\n' 'Forbidden mutating command found.' >&2
    exit 1
fi
if grep -En 'SHA256=TODO|SHA256=$' manifests/*.env; then
    printf '%s\n' 'Unpinned source checksum found.' >&2
    exit 1
fi
printf '%s\n' 'Analysis scripts passed syntax and safety checks.'
