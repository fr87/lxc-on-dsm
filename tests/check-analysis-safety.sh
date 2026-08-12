#!/bin/sh
set -eu
target=scripts/analyze-dsm.sh
sh -n "$target"
sh -n scripts/compare-reports.sh
forbidden='(^|[[:space:]])(mount|umount|modprobe|insmod|rmmod|sysctl[[:space:]]+-w|apk|apt|opkg|synopkg|iptables[[:space:]]+-|nft[[:space:]]+(add|delete|flush))([[:space:]]|$)'
if grep -En "$forbidden" "$target"; then
    printf '%s\n' 'Forbidden mutating command found.' >&2
    exit 1
fi
printf '%s\n' 'Analysis scripts passed syntax and safety checks.'
