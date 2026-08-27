#!/bin/sh
# Assemble a dry-run DSM package payload tree. Does not build or install an SPK.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--output DIRECTORY] [--runtime-bundle FILE] [--rootfs-tar FILE]"
}

package_name=lxc-on-dsm
output_root=build/spk-payload
runtime_bundle=
rootfs_tar=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_root=$2; shift 2 ;;
        --runtime-bundle) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; runtime_bundle=$2; shift 2 ;;
        --rootfs-tar) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; rootfs_tar=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
if [ -n "$runtime_bundle" ]; then
    [ -r "$runtime_bundle" ] || { printf 'Missing runtime bundle: %s\n' "$runtime_bundle" >&2; exit 1; }
    case "$runtime_bundle" in
        *.tar.gz|*.tgz) ;;
        *) printf 'Runtime bundle must end with .tar.gz or .tgz: %s\n' "$runtime_bundle" >&2; exit 2 ;;
    esac
fi
if [ -n "$rootfs_tar" ]; then
    [ -r "$rootfs_tar" ] || { printf 'Missing rootfs tar: %s\n' "$rootfs_tar" >&2; exit 1; }
    case "$rootfs_tar" in
        *.tar.gz|*.tgz) ;;
        *) printf 'Rootfs image must end with .tar.gz or .tgz: %s\n' "$rootfs_tar" >&2; exit 2 ;;
    esac
fi

payload_dir="${output_root}/${package_name}"
target_dir="${payload_dir}/target"
etc_dir="${payload_dir}/etc"
conf_dir="${payload_dir}/conf"
pkg_scripts_dir="${payload_dir}/scripts"

if [ -e "$payload_dir" ]; then
    printf 'Payload directory already exists, refusing to overwrite: %s\n' "$payload_dir" >&2
    exit 1
fi

mkdir -p "${target_dir}/scripts" "${target_dir}/config" "$etc_dir" "$conf_dir" "$pkg_scripts_dir"
mkdir -p "${target_dir}/hooks" "${etc_dir}/hooks"
if [ -d spk/ui ]; then
    mkdir -p "${target_dir}/ui"
    mkdir -p "${target_dir}/ui/images"
fi
if [ -n "$runtime_bundle" ]; then
    mkdir -p "${target_dir}/runtime"
fi
if [ -n "$rootfs_tar" ]; then
    mkdir -p "${target_dir}/images"
fi

cp spk/INFO.template "${payload_dir}/INFO"
cp spk/conf/privilege.template "${conf_dir}/privilege"
sed "s/%%PACKAGE_NAME%%/${package_name}/g" spk/scripts/start-stop-status.template >"${pkg_scripts_dir}/start-stop-status"
cp spk/scripts/preinst.template "${pkg_scripts_dir}/preinst"
cp spk/scripts/postinst.template "${pkg_scripts_dir}/postinst"
cp spk/scripts/preupgrade.template "${pkg_scripts_dir}/preupgrade"
cp spk/scripts/postupgrade.template "${pkg_scripts_dir}/postupgrade"
cp spk/scripts/preuninst.template "${pkg_scripts_dir}/preuninst"
cp spk/scripts/postuninst.template "${pkg_scripts_dir}/postuninst"
if [ -d spk/ui ]; then
    cp spk/ui/config "${target_dir}/ui/config"
    cp spk/ui/index.html "${target_dir}/ui/index.html"
    cp spk/ui/style.css "${target_dir}/ui/style.css"
    cp spk/ui/app.js "${target_dir}/ui/app.js"
    for icon_size in 16 24 32 48 64 72 256; do
        base64 -d spk/ui/images/icon.png.b64 >"${target_dir}/ui/images/icon_${icon_size}.png"
    done
fi

cp scripts/start-macvlan-profile.sh "${target_dir}/scripts/"
cp scripts/stop-macvlan-profile.sh "${target_dir}/scripts/"
cp scripts/doctor-macvlan-profile.sh "${target_dir}/scripts/"
cp scripts/verify-macvlan-profile.sh "${target_dir}/scripts/"
cp scripts/print-lxc-env.sh "${target_dir}/scripts/"
cp scripts/prepare-package-access.sh "${target_dir}/scripts/"
cp scripts/restore-lxc-runtime-bundle.sh "${target_dir}/scripts/"
cp scripts/check-lxc-runtime-deps.sh "${target_dir}/scripts/"
cp scripts/install-packaged-runtime.sh "${target_dir}/scripts/"
cp scripts/create-packaged-container.sh "${target_dir}/scripts/"
cp scripts/list-packaged-containers.sh "${target_dir}/scripts/"
cp scripts/install-packaged-start-hook.sh "${target_dir}/scripts/"
cp scripts/install-packaged-hook-snippet.sh "${target_dir}/scripts/"
cp scripts/start-packaged-container.sh "${target_dir}/scripts/"
cp scripts/stop-packaged-container.sh "${target_dir}/scripts/"
cp scripts/exec-packaged-container.sh "${target_dir}/scripts/"
cp scripts/run-packaged-smoke-test.sh "${target_dir}/scripts/"
cp scripts/run-packaged-macvlan-dhcp-test.sh "${target_dir}/scripts/"
cp scripts/experimental/lxc-on-dsm-root-helper.sh "${target_dir}/scripts/"
cp config/lab-macvlan.env.example "${etc_dir}/lab-macvlan.env.example"
cp config/lab-macvlan.env.example "${target_dir}/config/lab-macvlan.env.example"
cp spk/hooks/README.md "${target_dir}/hooks/README.md"
cp spk/hooks/marker.example.sh "${target_dir}/hooks/marker.example.sh"
if [ -n "$runtime_bundle" ]; then
    cp "$runtime_bundle" "${target_dir}/runtime/lxc-runtime-bundle.tar.gz"
    {
        printf '%s\n' '# Packaged LXC runtime bundle manifest'
        printf 'source_bundle=%s\n' "$runtime_bundle"
        printf 'packaged_bundle=target/runtime/lxc-runtime-bundle.tar.gz\n'
        printf 'generated_utc=%s\n' "$(date -u +%Y%m%dT%H%M%SZ)"
        printf '\n'
        printf '%s\n' '## Scope'
        printf '%s\n' '- bundle is shipped as an opaque artifact'
        printf '%s\n' '- package installation does not restore it automatically'
        printf '%s\n' '- package start does not create containers automatically'
    } >"${target_dir}/runtime/README.md"
fi
if [ -n "$rootfs_tar" ]; then
    cp "$rootfs_tar" "${target_dir}/images/alpine-minirootfs.tar.gz"
    {
        printf '%s\n' '# Packaged container image manifest'
        printf 'source_image=%s\n' "$rootfs_tar"
        printf 'packaged_image=target/images/alpine-minirootfs.tar.gz\n'
        printf 'generated_utc=%s\n' "$(date -u +%Y%m%dT%H%M%SZ)"
        printf '\n'
        printf '%s\n' '## Scope'
        printf '%s\n' '- image is shipped as an opaque root filesystem seed'
        printf '%s\n' '- package installation does not extract it automatically'
        printf '%s\n' '- containers are created only by an explicit admin command'
        printf '%s\n' '- container creation does not start the container'
    } >"${target_dir}/images/README.md"
fi
if [ -d spk/ui ]; then
    {
        printf '%s\n' '{'
        printf '  "package": "%s",\n' "$package_name"
        sed -n 's/^version="\([^"]*\)"$/  "version": "\1",/p' spk/INFO.template
        printf '  "mode": "experimental-lab",\n'
        if [ -n "$runtime_bundle" ]; then
            printf '%s\n' '  "runtime_bundle_packaged": true,'
        else
            printf '%s\n' '  "runtime_bundle_packaged": false,'
        fi
        if [ -n "$rootfs_tar" ]; then
            printf '%s\n' '  "alpine_image_packaged": true'
        else
            printf '%s\n' '  "alpine_image_packaged": false'
        fi
        printf '%s\n' '}'
    } >"${target_dir}/ui/status.json"
fi

chmod 0755 "$target_dir" "${target_dir}/scripts" "${target_dir}/config" \
    "$etc_dir" "$conf_dir" "$pkg_scripts_dir" \
    "${pkg_scripts_dir}/start-stop-status" \
    "${pkg_scripts_dir}/preinst" \
    "${pkg_scripts_dir}/postinst" \
    "${pkg_scripts_dir}/preupgrade" \
    "${pkg_scripts_dir}/postupgrade" \
    "${pkg_scripts_dir}/preuninst" \
    "${pkg_scripts_dir}/postuninst" \
    "${target_dir}/scripts/start-macvlan-profile.sh" \
    "${target_dir}/scripts/stop-macvlan-profile.sh" \
    "${target_dir}/scripts/doctor-macvlan-profile.sh" \
    "${target_dir}/scripts/verify-macvlan-profile.sh" \
    "${target_dir}/scripts/print-lxc-env.sh" \
    "${target_dir}/scripts/prepare-package-access.sh" \
    "${target_dir}/scripts/restore-lxc-runtime-bundle.sh" \
    "${target_dir}/scripts/check-lxc-runtime-deps.sh" \
    "${target_dir}/scripts/install-packaged-runtime.sh" \
    "${target_dir}/scripts/create-packaged-container.sh" \
    "${target_dir}/scripts/list-packaged-containers.sh" \
    "${target_dir}/scripts/install-packaged-start-hook.sh" \
    "${target_dir}/scripts/install-packaged-hook-snippet.sh" \
    "${target_dir}/scripts/start-packaged-container.sh" \
    "${target_dir}/scripts/stop-packaged-container.sh" \
    "${target_dir}/scripts/exec-packaged-container.sh" \
    "${target_dir}/scripts/run-packaged-smoke-test.sh" \
    "${target_dir}/scripts/run-packaged-macvlan-dhcp-test.sh" \
    "${target_dir}/scripts/lxc-on-dsm-root-helper.sh"
chmod 0644 "${etc_dir}/lab-macvlan.env.example" \
    "${target_dir}/config/lab-macvlan.env.example" \
    "${target_dir}/hooks/README.md" \
    "${target_dir}/hooks/marker.example.sh"
chmod 0755 "${target_dir}/hooks" "${etc_dir}/hooks"
if [ -n "$runtime_bundle" ]; then
    chmod 0755 "${target_dir}/runtime"
    chmod 0644 "${target_dir}/runtime/lxc-runtime-bundle.tar.gz" \
        "${target_dir}/runtime/README.md"
fi
if [ -d "${target_dir}/ui" ]; then
    chmod 0755 "${target_dir}/ui" "${target_dir}/ui/images"
    chmod 0644 "${target_dir}/ui/config" \
        "${target_dir}/ui/index.html" \
        "${target_dir}/ui/style.css" \
        "${target_dir}/ui/app.js" \
        "${target_dir}/ui/status.json" \
        "${target_dir}/ui/images/icon_16.png" \
        "${target_dir}/ui/images/icon_24.png" \
        "${target_dir}/ui/images/icon_32.png" \
        "${target_dir}/ui/images/icon_48.png" \
        "${target_dir}/ui/images/icon_64.png" \
        "${target_dir}/ui/images/icon_72.png" \
        "${target_dir}/ui/images/icon_256.png"
fi
if [ -n "$rootfs_tar" ]; then
    chmod 0755 "${target_dir}/images"
    chmod 0644 "${target_dir}/images/alpine-minirootfs.tar.gz" \
        "${target_dir}/images/README.md"
fi

{
    printf '%s\n' '# Dry-run SPK payload manifest'
    printf 'package=%s\n' "$package_name"
    printf 'payload_dir=%s\n' "$payload_dir"
    printf 'generated_utc=%s\n' "$(date -u +%Y%m%dT%H%M%SZ)"
    printf '\n'
    find "$payload_dir" -type f | sort
} >"${payload_dir}/PAYLOAD-MANIFEST.txt"

printf '%s\n' '# Dry-run SPK payload assembly'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'payload_dir=%s\n' "$payload_dir"
[ -z "$runtime_bundle" ] || printf 'runtime_bundle=%s\n' "$runtime_bundle"
[ -z "$rootfs_tar" ] || printf 'rootfs_tar=%s\n' "$rootfs_tar"
printf '\n'
printf '%s\n' 'Result: SPK PAYLOAD ASSEMBLED. No .spk was built or installed.'
