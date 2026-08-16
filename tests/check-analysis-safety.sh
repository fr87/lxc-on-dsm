#!/bin/sh
set -eu
for script in scripts/*.sh scripts/lib/*.sh scripts/experimental/*.sh; do
    [ -e "$script" ] || continue
    sh -n "$script"
done
forbidden='^[[:space:]]*(mount|umount|modprobe|insmod|rmmod|sysctl[[:space:]]+-w|apk[[:space:]]+(add|del)|apt[[:space:]]+(install|remove|purge)|opkg[[:space:]]+(install|remove|upgrade)|synopkg|iptables[[:space:]]+-|nft[[:space:]]+(add|delete|flush))([[:space:]]|$)'
if grep -En "$forbidden" scripts/*.sh scripts/lib/*.sh scripts/experimental/*.sh; then
    printf '%s\n' 'Forbidden mutating command found.' >&2
    exit 1
fi
if grep -En 'SHA256=TODO|SHA256=$' manifests/*.env; then
    printf '%s\n' 'Unpinned source checksum found.' >&2
    exit 1
fi
printf '%s\n' 'Analysis scripts passed syntax and safety checks.'
