#!/bin/sh
# Assemble a dry-run DSM package payload tree. Does not build or install an SPK.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--output DIRECTORY]"
}

package_name=lxc-on-dsm
output_root=build/spk-payload

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_root=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac

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

cp spk/INFO.template "${payload_dir}/INFO"
cp spk/conf/privilege.template "${conf_dir}/privilege"
sed "s/%%PACKAGE_NAME%%/${package_name}/g" spk/scripts/start-stop-status.template >"${pkg_scripts_dir}/start-stop-status"
cp spk/scripts/preinst.template "${pkg_scripts_dir}/preinst"
cp spk/scripts/postinst.template "${pkg_scripts_dir}/postinst"
cp spk/scripts/preupgrade.template "${pkg_scripts_dir}/preupgrade"
cp spk/scripts/postupgrade.template "${pkg_scripts_dir}/postupgrade"
cp spk/scripts/preuninst.template "${pkg_scripts_dir}/preuninst"
cp spk/scripts/postuninst.template "${pkg_scripts_dir}/postuninst"

cp scripts/start-macvlan-profile.sh "${target_dir}/scripts/"
cp scripts/stop-macvlan-profile.sh "${target_dir}/scripts/"
cp scripts/doctor-macvlan-profile.sh "${target_dir}/scripts/"
cp scripts/verify-macvlan-profile.sh "${target_dir}/scripts/"
cp scripts/print-lxc-env.sh "${target_dir}/scripts/"
cp scripts/prepare-package-access.sh "${target_dir}/scripts/"
cp config/lab-macvlan.env.example "${etc_dir}/lab-macvlan.env.example"
cp config/lab-macvlan.env.example "${target_dir}/config/lab-macvlan.env.example"

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
    "${target_dir}/scripts/prepare-package-access.sh"
chmod 0644 "${etc_dir}/lab-macvlan.env.example" \
    "${target_dir}/config/lab-macvlan.env.example"

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
printf '\n'
printf '%s\n' 'Result: SPK PAYLOAD ASSEMBLED. No .spk was built or installed.'
