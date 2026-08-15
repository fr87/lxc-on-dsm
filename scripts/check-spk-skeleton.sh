#!/bin/sh
# Validate the experimental SPK skeleton without building or installing a package.
set -eu

root_dir=spk

required_files="
spk/README.md
spk/INFO.template
spk/scripts/start-stop-status.template
spk/scripts/preinst.template
spk/scripts/postinst.template
spk/scripts/preupgrade.template
spk/scripts/postupgrade.template
spk/scripts/preuninst.template
"

missing=0
printf '%s\n' '# SPK skeleton check'
printf '\n'

for file in $required_files; do
    if [ -r "$file" ]; then
        printf 'OK: %s\n' "$file"
    else
        printf 'MISSING: %s\n' "$file"
        missing=$((missing + 1))
    fi
done

printf '\n'
if grep -RIn 'autostart.*enabled\|silent_install="yes"\|silent_upgrade="yes"\|silent_uninstall="yes"' "$root_dir" >/tmp/lxc-on-dsm-spk-check.$$ 2>/dev/null; then
    cat /tmp/lxc-on-dsm-spk-check.$$
    rm -f /tmp/lxc-on-dsm-spk-check.$$
    printf '%s\n' 'Result: SPK SKELETON BLOCKED. Unsafe package skeleton signal found.'
    exit 1
fi
rm -f /tmp/lxc-on-dsm-spk-check.$$

if ! grep -q '^startable="yes"$' spk/INFO.template; then
    printf '%s\n' 'MISSING: startable package metadata'
    missing=$((missing + 1))
fi
if ! grep -q 'doctor-macvlan-profile.sh' spk/scripts/start-stop-status.template; then
    printf '%s\n' 'MISSING: status wrapper does not call doctor'
    missing=$((missing + 1))
fi
if ! grep -q 'start-macvlan-profile.sh' spk/scripts/start-stop-status.template; then
    printf '%s\n' 'MISSING: start wrapper does not call profile lifecycle start'
    missing=$((missing + 1))
fi
if ! grep -q 'stop-macvlan-profile.sh' spk/scripts/start-stop-status.template; then
    printf '%s\n' 'MISSING: stop wrapper does not call profile lifecycle stop'
    missing=$((missing + 1))
fi

printf '\n'
if [ "$missing" -eq 0 ]; then
    printf '%s\n' 'Result: SPK SKELETON OK. No package was built or installed.'
else
    printf 'Result: SPK SKELETON INCOMPLETE: %s missing item(s). No package was built or installed.\n' "$missing"
    exit 1
fi
