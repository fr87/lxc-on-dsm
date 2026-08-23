#!/bin/sh
# Validate the experimental SPK skeleton without building or installing a package.
set -eu

root_dir=spk

required_files="
spk/README.md
spk/INFO.template
spk/conf/privilege.template
spk/scripts/start-stop-status.template
spk/scripts/preinst.template
spk/scripts/postinst.template
spk/scripts/preupgrade.template
spk/scripts/postupgrade.template
spk/scripts/preuninst.template
spk/scripts/postuninst.template
spk/ui/config
spk/ui/index.html
spk/ui/style.css
scripts/prepare-package-access.sh
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
if ! grep -q '^version="[0-9][0-9.]*-[0-9][0-9]*"$' spk/INFO.template; then
    printf '%s\n' 'MISSING: DSM-compatible numeric package version'
    missing=$((missing + 1))
fi
if ! grep -q '^os_min_ver="7\.0-40000"$' spk/INFO.template; then
    printf '%s\n' 'MISSING: DSM 7 compatible os_min_ver metadata'
    missing=$((missing + 1))
fi
if ! grep -q '^dsmuidir="ui"$' spk/INFO.template; then
    printf '%s\n' 'MISSING: DSM UI directory metadata'
    missing=$((missing + 1))
fi
if ! grep -q '^dsmappname="com\.fr87\.LxcOnDsmLab"$' spk/INFO.template; then
    printf '%s\n' 'MISSING: DSM app name metadata'
    missing=$((missing + 1))
fi
if ! grep -q '"com.fr87.LxcOnDsmLab"' spk/ui/config; then
    printf '%s\n' 'MISSING: DSM UI app config entry'
    missing=$((missing + 1))
fi
if ! grep -q '"url": "3rdparty/lxc-on-dsm/index.html"' spk/ui/config; then
    printf '%s\n' 'MISSING: DSM UI local URL config'
    missing=$((missing + 1))
fi
if ! grep -q '"run-as": "package"' spk/conf/privilege.template; then
    printf '%s\n' 'MISSING: DSM 7 package run-as declaration'
    missing=$((missing + 1))
fi
if grep -q '"ctrl-script"' spk/conf/privilege.template; then
    printf '%s\n' 'BLOCKED: package ctrl-script attributes are not used in the lab skeleton'
    missing=$((missing + 1))
fi
if grep -q '"tool"' spk/conf/privilege.template; then
    printf '%s\n' 'BLOCKED: package privilege tool attributes are not used in the lab skeleton'
    missing=$((missing + 1))
fi
if ! grep -q 'doctor-macvlan-profile.sh' spk/scripts/start-stop-status.template; then
    printf '%s\n' 'MISSING: status wrapper does not call doctor'
    missing=$((missing + 1))
fi
if ! grep -q 'lxc-on-dsm-root-helper.sh' spk/scripts/start-stop-status.template; then
    printf '%s\n' 'MISSING: start/stop wrapper does not point to installed root helper'
    missing=$((missing + 1))
fi
if ! grep -q 'exec sh "$HELPER" start' spk/scripts/start-stop-status.template; then
    printf '%s\n' 'MISSING: start wrapper does not delegate to root helper'
    missing=$((missing + 1))
fi
if ! grep -q 'exec sh "$HELPER" stop' spk/scripts/start-stop-status.template; then
    printf '%s\n' 'MISSING: stop wrapper does not delegate to root helper'
    missing=$((missing + 1))
fi
if ! grep -q 'requires root on DSM' spk/scripts/start-stop-status.template; then
    printf '%s\n' 'MISSING: start/stop wrapper does not explain root lifecycle gate'
    missing=$((missing + 1))
fi

printf '\n'
if [ "$missing" -eq 0 ]; then
    printf '%s\n' 'Result: SPK SKELETON OK. No package was built or installed.'
else
    printf 'Result: SPK SKELETON INCOMPLETE: %s missing item(s). No package was built or installed.\n' "$missing"
    exit 1
fi
