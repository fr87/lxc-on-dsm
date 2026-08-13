#!/bin/sh
set -eu
target=scripts/analyze-dsm.sh
for script in scripts/analyze-dsm.sh scripts/compare-reports.sh scripts/evaluate-report.sh; do
    sh -n "$script"
done
forbidden='(^|[[:space:]])(mount|umount|modprobe|insmod|rmmod|sysctl[[:space:]]+-w|apk|apt|opkg|synopkg|iptables[[:space:]]+-|nft[[:space:]]+(add|delete|flush))([[:space:]]|$)'
if grep -En "$forbidden" scripts/*.sh; then
    printf '%s\n' 'Forbidden mutating command found.' >&2
    exit 1
fi
printf '%s\n' 'Analysis scripts passed syntax and safety checks.'
