#!/bin/sh
# Inspect an experimental DSM SPK archive. Does not install or execute it.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --spk FILE [--require-runtime-bundle] [--require-alpine-image]"
}

spk_file=
require_runtime_bundle=0
require_alpine_image=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --spk) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; spk_file=$2; shift 2 ;;
        --require-runtime-bundle) require_runtime_bundle=1; shift ;;
        --require-alpine-image) require_alpine_image=1; shift ;;
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
printf 'require_runtime_bundle=%s\n' "$require_runtime_bundle"
printf 'require_alpine_image=%s\n' "$require_alpine_image"
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
    grep -q '^dsmuidir="ui"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: package metadata dsmuidir' || { printf '%s\n' 'MISSING: DSM UI directory metadata'; missing=$((missing + 1)); }
    grep -q '^dsmappname="com\.fr87\.LxcOnDsmLab"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: package metadata dsmappname' || { printf '%s\n' 'MISSING: DSM app name metadata'; missing=$((missing + 1)); }
    grep -q '^silent_install="no"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: silent_install disabled' || { printf '%s\n' 'MISSING: silent_install disabled'; missing=$((missing + 1)); }
    grep -q '^silent_upgrade="no"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: silent_upgrade disabled' || { printf '%s\n' 'MISSING: silent_upgrade disabled'; missing=$((missing + 1)); }
    grep -q '^silent_uninstall="no"$' "${tmp_dir}/INFO" && printf '%s\n' 'OK: silent_uninstall disabled' || { printf '%s\n' 'MISSING: silent_uninstall disabled'; missing=$((missing + 1)); }
fi

if [ -r "${tmp_dir}/conf/privilege" ]; then
    grep -q '"run-as": "package"' "${tmp_dir}/conf/privilege" && printf '%s\n' 'OK: package run-as declaration' || { printf '%s\n' 'MISSING: DSM 7 package run-as declaration'; missing=$((missing + 1)); }
    if grep -q '"ctrl-script"' "${tmp_dir}/conf/privilege"; then
        printf '%s\n' 'BLOCKED: package ctrl-script attributes are not used in the lab skeleton'
        missing=$((missing + 1))
    else
        printf '%s\n' 'OK: package avoids ctrl-script attribute rewrites'
    fi
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
    grep -q 'scripts/restore-lxc-runtime-bundle.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target runtime restore script present' || { printf '%s\n' 'MISSING: target runtime restore script'; missing=$((missing + 1)); }
    grep -q 'scripts/check-lxc-runtime-deps.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target runtime dependency check present' || { printf '%s\n' 'MISSING: target runtime dependency check'; missing=$((missing + 1)); }
    grep -q 'scripts/install-packaged-runtime.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged runtime install wrapper present' || { printf '%s\n' 'MISSING: target packaged runtime install wrapper'; missing=$((missing + 1)); }
    grep -q 'scripts/create-packaged-container.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged container create script present' || { printf '%s\n' 'MISSING: target packaged container create script'; missing=$((missing + 1)); }
    grep -q 'scripts/list-packaged-containers.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged container inventory script present' || { printf '%s\n' 'MISSING: target packaged container inventory script'; missing=$((missing + 1)); }
    grep -q 'scripts/install-packaged-start-hook.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged start hook installer present' || { printf '%s\n' 'MISSING: target packaged start hook installer'; missing=$((missing + 1)); }
    grep -q 'scripts/install-packaged-hook-snippet.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged hook snippet installer present' || { printf '%s\n' 'MISSING: target packaged hook snippet installer'; missing=$((missing + 1)); }
    grep -q 'scripts/start-packaged-container.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged container start script present' || { printf '%s\n' 'MISSING: target packaged container start script'; missing=$((missing + 1)); }
    grep -q 'scripts/stop-packaged-container.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged container stop script present' || { printf '%s\n' 'MISSING: target packaged container stop script'; missing=$((missing + 1)); }
    grep -q 'scripts/remove-packaged-container.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged container remove script present' || { printf '%s\n' 'MISSING: target packaged container remove script'; missing=$((missing + 1)); }
    grep -q 'scripts/exec-packaged-container.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged container exec script present' || { printf '%s\n' 'MISSING: target packaged container exec script'; missing=$((missing + 1)); }
    grep -q 'scripts/run-packaged-smoke-test.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged smoke test present' || { printf '%s\n' 'MISSING: target packaged smoke test'; missing=$((missing + 1)); }
    grep -q 'scripts/run-packaged-macvlan-dhcp-test.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target packaged macvlan DHCP test present' || { printf '%s\n' 'MISSING: target packaged macvlan DHCP test'; missing=$((missing + 1)); }
    grep -q 'scripts/lxc-on-dsm-root-helper.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target root helper present' || { printf '%s\n' 'MISSING: target root helper'; missing=$((missing + 1)); }
    grep -q 'config/lab-macvlan.env.example' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target profile example present' || { printf '%s\n' 'MISSING: target profile example'; missing=$((missing + 1)); }
    grep -q 'ui/config' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target DSM UI config present' || { printf '%s\n' 'MISSING: target DSM UI config'; missing=$((missing + 1)); }
    grep -q 'ui/index.html' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target DSM UI page present' || { printf '%s\n' 'MISSING: target DSM UI page'; missing=$((missing + 1)); }
    grep -q 'ui/style.css' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target DSM UI style present' || { printf '%s\n' 'MISSING: target DSM UI style'; missing=$((missing + 1)); }
    grep -q 'ui/app.js' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target DSM UI script present' || { printf '%s\n' 'MISSING: target DSM UI script'; missing=$((missing + 1)); }
    grep -q 'ui/status.json' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target DSM UI status manifest present' || { printf '%s\n' 'MISSING: target DSM UI status manifest'; missing=$((missing + 1)); }
    grep -q 'ui/images/icon_64.png' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target DSM UI icon present' || { printf '%s\n' 'MISSING: target DSM UI icon'; missing=$((missing + 1)); }
    grep -q '"url": "3rdparty/lxc-on-dsm/index.html"' "${tmp_dir}/package/ui/config" && printf '%s\n' 'OK: DSM UI local URL config' || { printf '%s\n' 'MISSING: DSM UI local URL config'; missing=$((missing + 1)); }
    grep -q '"icon": "images/icon_{0}.png"' "${tmp_dir}/package/ui/config" && printf '%s\n' 'OK: DSM UI icon config' || { printf '%s\n' 'MISSING: DSM UI icon config'; missing=$((missing + 1)); }
    grep -q 'Package Center start/stop is intentionally blocked' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI explains root lifecycle gate' || { printf '%s\n' 'MISSING: DSM UI root lifecycle warning'; missing=$((missing + 1)); }
    grep -q 'id="command-builder-title"' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI command builder present' || { printf '%s\n' 'MISSING: DSM UI command builder'; missing=$((missing + 1)); }
    grep -q 'list-packaged-containers.sh' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI includes container inventory command' || { printf '%s\n' 'MISSING: DSM UI container inventory command'; missing=$((missing + 1)); }
    grep -q 'start-packaged-container.sh' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI includes packaged start command' || { printf '%s\n' 'MISSING: DSM UI packaged start command'; missing=$((missing + 1)); }
    grep -q 'install-packaged-start-hook.sh' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI includes packaged start hook command' || { printf '%s\n' 'MISSING: DSM UI packaged start hook command'; missing=$((missing + 1)); }
    grep -q 'install-packaged-hook-snippet.sh' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI includes packaged hook snippet command' || { printf '%s\n' 'MISSING: DSM UI packaged hook snippet command'; missing=$((missing + 1)); }
    grep -q 'stop-packaged-container.sh' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI includes packaged stop command' || { printf '%s\n' 'MISSING: DSM UI packaged stop command'; missing=$((missing + 1)); }
    grep -q 'remove-packaged-container.sh' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI includes packaged remove command' || { printf '%s\n' 'MISSING: DSM UI packaged remove command'; missing=$((missing + 1)); }
    grep -q 'exec-packaged-container.sh' "${tmp_dir}/package/ui/index.html" && printf '%s\n' 'OK: DSM UI includes packaged exec command' || { printf '%s\n' 'MISSING: DSM UI packaged exec command'; missing=$((missing + 1)); }
    grep -q 'navigator.clipboard' "${tmp_dir}/package/ui/app.js" && printf '%s\n' 'OK: DSM UI copy-to-clipboard helper present' || { printf '%s\n' 'MISSING: DSM UI copy-to-clipboard helper'; missing=$((missing + 1)); }
    grep -q 'safeInterface' "${tmp_dir}/package/ui/app.js" && printf '%s\n' 'OK: DSM UI constrains interface input' || { printf '%s\n' 'MISSING: DSM UI constrained interface helper'; missing=$((missing + 1)); }
    grep -q -- '--logfile' "${tmp_dir}/package/scripts/start-macvlan-profile.sh" && printf '%s\n' 'OK: start script captures LXC debug logfile' || { printf '%s\n' 'MISSING: start script LXC debug logfile capture'; missing=$((missing + 1)); }
    grep -q '0730' "${tmp_dir}/package/scripts/prepare-package-access.sh" && printf '%s\n' 'OK: package access can allow lifecycle-state writes' || { printf '%s\n' 'MISSING: package access lifecycle-state write permission'; missing=$((missing + 1)); }
    grep -q 'LXC RUNTIME RESTORE DRY RUN PASS' "${tmp_dir}/package/scripts/restore-lxc-runtime-bundle.sh" && printf '%s\n' 'OK: runtime restore script defaults to dry-run' || { printf '%s\n' 'MISSING: runtime restore dry-run gate'; missing=$((missing + 1)); }
    grep -q 'No container was started' "${tmp_dir}/package/scripts/check-lxc-runtime-deps.sh" && printf '%s\n' 'OK: runtime dependency check does not start containers' || { printf '%s\n' 'MISSING: runtime dependency no-container guarantee'; missing=$((missing + 1)); }
    grep -q 'Packaged LXC runtime restore' "${tmp_dir}/package/scripts/install-packaged-runtime.sh" && printf '%s\n' 'OK: packaged runtime install wrapper emits summary' || { printf '%s\n' 'MISSING: packaged runtime install wrapper summary'; missing=$((missing + 1)); }
    grep -q -- '--install' "${tmp_dir}/package/scripts/install-packaged-runtime.sh" && printf '%s\n' 'OK: packaged runtime install wrapper requires explicit install' || { printf '%s\n' 'MISSING: packaged runtime install wrapper explicit install gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER CREATE DRY RUN COMPLETE' "${tmp_dir}/package/scripts/create-packaged-container.sh" && printf '%s\n' 'OK: packaged container create script defaults to dry-run' || { printf '%s\n' 'MISSING: packaged container create dry-run gate'; missing=$((missing + 1)); }
    grep -q 'No container was started' "${tmp_dir}/package/scripts/create-packaged-container.sh" && printf '%s\n' 'OK: packaged container create script does not start containers' || { printf '%s\n' 'MISSING: packaged container create no-start guarantee'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER INVENTORY COMPLETE' "${tmp_dir}/package/scripts/list-packaged-containers.sh" && printf '%s\n' 'OK: packaged container inventory script present' || { printf '%s\n' 'MISSING: packaged container inventory success marker'; missing=$((missing + 1)); }
    grep -q 'No container was started' "${tmp_dir}/package/scripts/list-packaged-containers.sh" && printf '%s\n' 'OK: packaged container inventory is read-only' || { printf '%s\n' 'MISSING: packaged container inventory no-start guarantee'; missing=$((missing + 1)); }
    grep -q 'PACKAGED START HOOK INSTALL DRY RUN COMPLETE' "${tmp_dir}/package/scripts/install-packaged-start-hook.sh" && printf '%s\n' 'OK: packaged start hook installer defaults to dry-run' || { printf '%s\n' 'MISSING: packaged start hook install dry-run gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED START HOOK INSTALLED' "${tmp_dir}/package/scripts/install-packaged-start-hook.sh" && printf '%s\n' 'OK: packaged start hook installer success marker present' || { printf '%s\n' 'MISSING: packaged start hook install success marker'; missing=$((missing + 1)); }
    grep -q 'No container was started' "${tmp_dir}/package/scripts/install-packaged-start-hook.sh" && printf '%s\n' 'OK: packaged start hook installer does not start containers' || { printf '%s\n' 'MISSING: packaged start hook install no-start guarantee'; missing=$((missing + 1)); }
    grep -q 'PACKAGED HOOK SNIPPET INSTALL DRY RUN COMPLETE' "${tmp_dir}/package/scripts/install-packaged-hook-snippet.sh" && printf '%s\n' 'OK: packaged hook snippet installer defaults to dry-run' || { printf '%s\n' 'MISSING: packaged hook snippet install dry-run gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED HOOK SNIPPET INSTALLED' "${tmp_dir}/package/scripts/install-packaged-hook-snippet.sh" && printf '%s\n' 'OK: packaged hook snippet installer success marker present' || { printf '%s\n' 'MISSING: packaged hook snippet install success marker'; missing=$((missing + 1)); }
    grep -q 'No container was started' "${tmp_dir}/package/scripts/install-packaged-hook-snippet.sh" && printf '%s\n' 'OK: packaged hook snippet installer does not start containers' || { printf '%s\n' 'MISSING: packaged hook snippet install no-start guarantee'; missing=$((missing + 1)); }
    grep -q 'hooks/marker.example.sh' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: target marker hook example present' || { printf '%s\n' 'MISSING: target marker hook example'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER START DRY RUN COMPLETE' "${tmp_dir}/package/scripts/start-packaged-container.sh" && printf '%s\n' 'OK: packaged container start defaults to dry-run' || { printf '%s\n' 'MISSING: packaged container start dry-run gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER STARTED' "${tmp_dir}/package/scripts/start-packaged-container.sh" && printf '%s\n' 'OK: packaged container start success marker present' || { printf '%s\n' 'MISSING: packaged container start success marker'; missing=$((missing + 1)); }
    grep -q 'Packaged container start requires uid=0' "${tmp_dir}/package/scripts/start-packaged-container.sh" && printf '%s\n' 'OK: packaged container start has root gate' || { printf '%s\n' 'MISSING: packaged container start root gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER STOPPED' "${tmp_dir}/package/scripts/stop-packaged-container.sh" && printf '%s\n' 'OK: packaged container stop success marker present' || { printf '%s\n' 'MISSING: packaged container stop success marker'; missing=$((missing + 1)); }
    grep -q 'Packaged container stop requires uid=0' "${tmp_dir}/package/scripts/stop-packaged-container.sh" && printf '%s\n' 'OK: packaged container stop has root gate' || { printf '%s\n' 'MISSING: packaged container stop root gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER REMOVE DRY RUN COMPLETE' "${tmp_dir}/package/scripts/remove-packaged-container.sh" && printf '%s\n' 'OK: packaged container remove defaults to dry-run' || { printf '%s\n' 'MISSING: packaged container remove dry-run gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER REMOVED' "${tmp_dir}/package/scripts/remove-packaged-container.sh" && printf '%s\n' 'OK: packaged container remove success marker present' || { printf '%s\n' 'MISSING: packaged container remove success marker'; missing=$((missing + 1)); }
    grep -q 'Refusing to remove running container' "${tmp_dir}/package/scripts/remove-packaged-container.sh" && printf '%s\n' 'OK: packaged container remove refuses running containers' || { printf '%s\n' 'MISSING: packaged container remove running guard'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER EXEC DRY RUN COMPLETE' "${tmp_dir}/package/scripts/exec-packaged-container.sh" && printf '%s\n' 'OK: packaged container exec defaults to dry-run' || { printf '%s\n' 'MISSING: packaged container exec dry-run gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED CONTAINER EXEC COMPLETE' "${tmp_dir}/package/scripts/exec-packaged-container.sh" && printf '%s\n' 'OK: packaged container exec success marker present' || { printf '%s\n' 'MISSING: packaged container exec success marker'; missing=$((missing + 1)); }
    grep -q 'Packaged container exec requires uid=0' "${tmp_dir}/package/scripts/exec-packaged-container.sh" && printf '%s\n' 'OK: packaged container exec has root gate' || { printf '%s\n' 'MISSING: packaged container exec root gate'; missing=$((missing + 1)); }
    grep -q 'PACKAGED SMOKE TEST PASSED' "${tmp_dir}/package/scripts/run-packaged-smoke-test.sh" && printf '%s\n' 'OK: packaged smoke test success marker present' || { printf '%s\n' 'MISSING: packaged smoke test success marker'; missing=$((missing + 1)); }
    grep -q 'lxc.net.0.type = none' "${tmp_dir}/package/scripts/run-packaged-smoke-test.sh" && printf '%s\n' 'OK: packaged smoke test requires networkless config' || { printf '%s\n' 'MISSING: packaged smoke test networkless guard'; missing=$((missing + 1)); }
    grep -q 'PACKAGED MACVLAN DHCP TEST DRY RUN COMPLETE' "${tmp_dir}/package/scripts/run-packaged-macvlan-dhcp-test.sh" && printf '%s\n' 'OK: packaged macvlan DHCP test defaults to dry-run' || { printf '%s\n' 'MISSING: packaged macvlan DHCP dry-run gate'; missing=$((missing + 1)); }
    grep -q 'lxc.net.0.type = macvlan' "${tmp_dir}/package/scripts/run-packaged-macvlan-dhcp-test.sh" && printf '%s\n' 'OK: packaged macvlan DHCP test requires macvlan config' || { printf '%s\n' 'MISSING: packaged macvlan DHCP config guard'; missing=$((missing + 1)); }
    if [ -r "${tmp_dir}/package/scripts/lxc-on-dsm-root-helper.sh" ]; then
        grep -q 'ROOT HELPER DRY RUN COMPLETE' "${tmp_dir}/package/scripts/lxc-on-dsm-root-helper.sh" && printf '%s\n' 'OK: root helper dry-run guard present' || { printf '%s\n' 'MISSING: root helper dry-run guard'; missing=$((missing + 1)); }
        helper_mode=$(ls -l "${tmp_dir}/package/scripts/lxc-on-dsm-root-helper.sh" 2>/dev/null | awk '{ print $1 }' | sed -n '1p')
        case "$helper_mode" in
            -rwxr-xr-x) printf '%s\n' 'OK: root helper is executable without setuid' ;;
            *s*) printf 'BLOCKED: root helper appears to have setuid/setgid mode: %s\n' "$helper_mode"; missing=$((missing + 1)) ;;
            *) printf 'BLOCKED: root helper has unexpected mode: %s\n' "$helper_mode"; missing=$((missing + 1)) ;;
        esac
    fi
    if grep -q 'volume1/@lxc\|lifecycle-state.env\|containers/.*/rootfs\|/rootfs/' "${tmp_dir}/package-files.txt"; then
        printf '%s\n' 'BLOCKED: archive appears to contain runtime/container data'
        missing=$((missing + 1))
    fi
    for blocked_tool in gcc g++ cc c++ make meson ninja pkg-config pkgconf opkg; do
        if grep -qx "$blocked_tool" "${tmp_dir}/package-files.txt" || grep -q "/${blocked_tool}$" "${tmp_dir}/package-files.txt"; then
            printf 'BLOCKED: archive contains build/package-manager tool: %s\n' "$blocked_tool"
            missing=$((missing + 1))
        fi
    done
    if grep -q 'runtime/lxc-runtime-bundle.tar.gz' "${tmp_dir}/package-files.txt"; then
        printf '%s\n' 'OK: packaged runtime bundle present'
        grep -q 'runtime/README.md' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: packaged runtime bundle manifest present' || { printf '%s\n' 'MISSING: packaged runtime bundle manifest'; missing=$((missing + 1)); }
        if ! grep -q 'does not restore it automatically' "${tmp_dir}/package/runtime/README.md"; then
            printf '%s\n' 'MISSING: packaged runtime manifest no-autorestore note'
            missing=$((missing + 1))
        fi
        if tar -tzf "${tmp_dir}/package/runtime/lxc-runtime-bundle.tar.gz" >"${tmp_dir}/runtime-bundle-files.txt" 2>"${tmp_dir}/runtime-bundle-tar.err"; then
            grep -q 'runtime/bin/lxc-start' "${tmp_dir}/runtime-bundle-files.txt" && printf '%s\n' 'OK: packaged runtime bundle contains lxc-start' || { printf '%s\n' 'MISSING: packaged runtime bundle lxc-start'; missing=$((missing + 1)); }
            grep -q 'runtime/lib' "${tmp_dir}/runtime-bundle-files.txt" && printf '%s\n' 'OK: packaged runtime bundle contains runtime lib path' || { printf '%s\n' 'MISSING: packaged runtime bundle runtime lib path'; missing=$((missing + 1)); }
            if grep -q '/containers/\|/containers$' "${tmp_dir}/runtime-bundle-files.txt"; then
                printf '%s\n' 'BLOCKED: packaged runtime bundle appears to contain container/rootfs data'
                missing=$((missing + 1))
            else
                printf '%s\n' 'OK: packaged runtime bundle listing has no container data'
            fi
            if grep -q '/build/work/\|/build/sources/\|build.ninja\|meson-private\|meson-info' "${tmp_dir}/runtime-bundle-files.txt"; then
                printf '%s\n' 'BLOCKED: packaged runtime bundle appears to contain build intermediates'
                missing=$((missing + 1))
            else
                printf '%s\n' 'OK: packaged runtime bundle listing has no build intermediates'
            fi
        else
            cat "${tmp_dir}/runtime-bundle-tar.err"
            printf '%s\n' 'BLOCKED: packaged runtime bundle could not be listed'
            missing=$((missing + 1))
        fi
    else
        printf '%s\n' 'WARN: archive does not include a runtime bundle; package is management-only'
        if [ "$require_runtime_bundle" -eq 1 ]; then
            printf '%s\n' 'MISSING: runtime-bundled release candidate requires runtime/lxc-runtime-bundle.tar.gz'
            missing=$((missing + 1))
        fi
    fi
    if grep -q 'images/alpine-minirootfs.tar.gz' "${tmp_dir}/package-files.txt"; then
        printf '%s\n' 'OK: packaged Alpine image present'
        grep -q 'images/README.md' "${tmp_dir}/package-files.txt" && printf '%s\n' 'OK: packaged Alpine image manifest present' || { printf '%s\n' 'MISSING: packaged Alpine image manifest'; missing=$((missing + 1)); }
        if ! grep -q 'does not extract it automatically' "${tmp_dir}/package/images/README.md"; then
            printf '%s\n' 'MISSING: packaged Alpine image no-autoextract note'
            missing=$((missing + 1))
        fi
    else
        printf '%s\n' 'WARN: archive does not include an Alpine image; package cannot create a default container offline'
        if [ "$require_alpine_image" -eq 1 ]; then
            printf '%s\n' 'MISSING: runtime-bundled release candidate requires images/alpine-minirootfs.tar.gz'
            missing=$((missing + 1))
        fi
    fi
    if grep -q 'build.ninja\|meson-private\|meson-info\|/build/work/\|/build/sources/' "${tmp_dir}/package-files.txt"; then
        printf '%s\n' 'BLOCKED: archive contains build intermediates or source/build trees'
        missing=$((missing + 1))
    fi
fi

if [ -r "${tmp_dir}/scripts/start-stop-status" ]; then
    grep -q '/var/packages/${PACKAGE}/var/artifacts' "${tmp_dir}/scripts/start-stop-status" && printf '%s\n' 'OK: wrapper uses package-owned artifact path' || { printf '%s\n' 'MISSING: wrapper package-owned artifact path'; missing=$((missing + 1)); }
    grep -q 'requires root on DSM' "${tmp_dir}/scripts/start-stop-status" && printf '%s\n' 'OK: wrapper explains root lifecycle gate' || { printf '%s\n' 'MISSING: wrapper root lifecycle gate explanation'; missing=$((missing + 1)); }
    grep -q 'lxc-on-dsm-root-helper.sh' "${tmp_dir}/scripts/start-stop-status" && printf '%s\n' 'OK: wrapper points to installed root helper' || { printf '%s\n' 'MISSING: wrapper installed root helper hint'; missing=$((missing + 1)); }
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
