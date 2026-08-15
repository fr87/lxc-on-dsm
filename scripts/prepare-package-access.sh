#!/bin/sh
# Prepare minimal lab container access for the DSM package user.
# Default mode is read-only; pass --apply to change permissions.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--profile FILE] [--user USER] [--apply]"
}

profile_file=config/lab-macvlan.env
package_user=lxc_on_dsm
apply=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        --user) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_user=$2; shift 2 ;;
        --apply) apply=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_user" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package user: %s\n' "$package_user" >&2; exit 2 ;; esac
[ -r "$profile_file" ] || { printf 'Missing profile: %s\n' "$profile_file" >&2; exit 1; }
. "$profile_file"

state_dir=${LXC_LAB_STATE_DIR:-}
name=${LXC_LAB_CONTAINER:-}

[ -n "$state_dir" ] || { printf 'Profile missing LXC_LAB_STATE_DIR\n' >&2; exit 1; }
[ -n "$name" ] || { printf 'Profile missing LXC_LAB_CONTAINER\n' >&2; exit 1; }
case "$state_dir" in /volume1/@lxc/*|/volume[0-9]/@lxc/*) ;; *) printf 'Refusing non-lab state dir: %s\n' "$state_dir" >&2; exit 1 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 1 ;; esac
id "$package_user" >/dev/null 2>&1 || { printf 'Missing package user: %s\n' "$package_user" >&2; exit 1; }

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
rootfs_dir="${container_dir}/rootfs"

[ -d "$state_dir" ] || { printf 'Missing state dir: %s\n' "$state_dir" >&2; exit 1; }
[ -d "$container_dir" ] || { printf 'Missing container dir: %s\n' "$container_dir" >&2; exit 1; }
[ -f "$config_file" ] || { printf 'Missing container config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing container rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }

printf '%s\n' '# LXC package access preparation'
printf '\n'
printf 'profile=%s\n' "$profile_file"
printf 'package_user=%s\n' "$package_user"
printf 'state_dir=%s\n' "$state_dir"
printf 'container=%s\n' "$name"
printf 'container_dir=%s\n' "$container_dir"
printf 'config=%s\n' "$config_file"
printf 'rootfs=%s\n' "$rootfs_dir"
printf 'mode=%s\n' "$([ "$apply" -eq 1 ] && printf apply || printf plan)"
printf '\n'

printf '%s\n' 'Current access evidence:'
ls -ld "$state_dir" "$container_dir" "$rootfs_dir"
ls -l "$config_file"
su -s /bin/sh "$package_user" -c "test -x '$state_dir'; echo state_dir_traverse=\$?"
su -s /bin/sh "$package_user" -c "test -x '$container_dir'; echo container_traverse=\$?"
su -s /bin/sh "$package_user" -c "test -r '$config_file'; echo config_read=\$?"
su -s /bin/sh "$package_user" -c "test -x '$rootfs_dir'; echo rootfs_traverse=\$?"
printf '\n'

printf '%s\n' 'Required changes:'
printf 'chmod 0711 %s\n' "$state_dir"
printf 'chmod 0711 %s\n' "$container_dir"
printf 'chmod 0644 %s\n' "$config_file"
printf '\n'

if [ "$apply" -eq 0 ]; then
    printf '%s\n' 'Result: PACKAGE ACCESS PLAN READY. No permissions were changed.'
    printf 'Apply explicitly with: %s --profile %s --user %s --apply\n' "$0" "$profile_file" "$package_user"
    exit 0
fi

chmod 0711 "$state_dir"
chmod 0711 "$container_dir"
chmod 0644 "$config_file"

printf '%s\n' 'Access evidence after apply:'
ls -ld "$state_dir" "$container_dir" "$rootfs_dir"
ls -l "$config_file"
su -s /bin/sh "$package_user" -c "test -x '$state_dir'; echo state_dir_traverse=\$?"
su -s /bin/sh "$package_user" -c "test -x '$container_dir'; echo container_traverse=\$?"
su -s /bin/sh "$package_user" -c "test -r '$config_file'; echo config_read=\$?"
su -s /bin/sh "$package_user" -c "test -x '$rootfs_dir'; echo rootfs_traverse=\$?"

printf '\n'
printf '%s\n' 'Result: PACKAGE ACCESS PREPARED. Container rootfs contents were not modified.'
