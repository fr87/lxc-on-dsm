#!/bin/sh
# Generate a Virtual DSM installation test plan for the experimental SPK.
# Does not install a package or execute package scripts.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--spk FILE] [--profile FILE] [--output DIRECTORY]"
}

package_name=lxc-on-dsm
spk_file=build/spk/lxc-on-dsm-0.1.0-0010.spk
profile_file=config/lab-macvlan.env
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --spk) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; spk_file=$2; shift 2 ;;
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
case "$spk_file" in *.spk) ;; *) printf 'SPK path must end with .spk: %s\n' "$spk_file" >&2; exit 2 ;; esac

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
plan_file="${output_dir}/spk-install-plan-${stamp}.md"

{
    printf '%s\n' '# Virtual DSM SPK installation test plan'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'package=%s\n' "$package_name"
    printf 'spk=%s\n' "$spk_file"
    printf 'profile=%s\n' "$profile_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- plan only'
    printf '%s\n' '- Virtual DSM lab system only'
    printf '%s\n' '- does not install a package'
    printf '%s\n' '- does not execute package scripts'
    printf '%s\n' '- does not start containers'
    printf '%s\n' '- does not change networking'
    printf '\n'
    printf '%s\n' '## Required preconditions'
    printf '\n'
    printf '%s\n' '1. Virtual DSM snapshot exists and rollback was reviewed.'
    printf '%s\n' '2. Current shell is root on the Virtual DSM lab system.'
    printf '%s\n' '3. `scripts/doctor-macvlan-profile.sh` reports a clean idle state.'
    printf '%s\n' '4. `scripts/check-spk-archive.sh` reports the archive is OK.'
    printf '%s\n' '5. The package is not already installed, or uninstall/reinstall is explicitly planned.'
    printf '%s\n' '6. Container autostart remains disabled.'
    printf '%s\n' '7. Package installation and root lifecycle start are separate gates; Package Center start/stop is expected to block until a Resource Worker design exists.'
    printf '\n'
    printf '%s\n' '## Pre-install read-only checks'
    printf '\n'
    printf '```sh\n'
    printf 'sh scripts/doctor-macvlan-profile.sh --profile %s\n' "$profile_file"
    printf 'sh scripts/check-spk-archive.sh --spk %s\n' "$spk_file"
    printf 'synopkg status %s\n' "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' '`synopkg status` may report that the package is not installed; that is acceptable before the first install.'
    printf '\n'
    printf '%s\n' '## Installation options'
    printf '\n'
    printf '%s\n' 'Preferred first attempt: manual upload through DSM Package Center in Virtual DSM.'
    printf '\n'
    printf '%s\n' 'CLI alternative, only after reviewing the preconditions:'
    printf '\n'
    printf '```sh\n'
    printf '/usr/syno/bin/synopkg install %s\n' "$spk_file"
    printf '```\n'
    printf '\n'
    printf '%s\n' 'Do not start the package automatically after install.'
    printf '%s\n' 'If installation still fails before `/var/packages` is created, collect the exact `synopkg install` JSON and do not retry with modified runtime state.'
    printf '\n'
    printf '%s\n' '## Post-install checks before start'
    printf '\n'
    printf '```sh\n'
    printf '/usr/syno/bin/synopkg status %s\n' "$package_name"
    printf 'ls -la /var/packages/%s\n' "$package_name"
    printf 'ls -la /var/packages/%s/target\n' "$package_name"
    printf 'ls -la /var/packages/%s/etc\n' "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' 'Before package start, copy or generate a reviewed profile at the package-owned path:'
    printf '\n'
    printf '```sh\n'
    printf 'mkdir -p /var/packages/%s/etc\n' "$package_name"
    printf 'cp %s /var/packages/%s/etc/lab-macvlan.env\n' "$profile_file" "$package_name"
    printf 'chown lxc_on_dsm:lxc_on_dsm /var/packages/%s/etc/lab-macvlan.env\n' "$package_name"
    printf 'chmod 0640 /var/packages/%s/etc/lab-macvlan.env\n' "$package_name"
    printf 'su -s /bin/sh lxc_on_dsm -c '"'"'test -r /var/packages/%s/etc/lab-macvlan.env; echo profile_read=$?'"'"'\n' "$package_name"
    printf 'sh /var/packages/%s/target/scripts/prepare-package-access.sh --profile /var/packages/%s/etc/lab-macvlan.env --user lxc_on_dsm\n' "$package_name" "$package_name"
    printf 'sh /var/packages/%s/target/scripts/prepare-package-access.sh --profile /var/packages/%s/etc/lab-macvlan.env --user lxc_on_dsm --apply\n' "$package_name" "$package_name"
    printf 'sh /var/packages/%s/target/scripts/verify-macvlan-profile.sh --profile /var/packages/%s/etc/lab-macvlan.env\n' "$package_name" "$package_name"
    printf 'sh /var/packages/%s/target/scripts/doctor-macvlan-profile.sh --profile /var/packages/%s/etc/lab-macvlan.env\n' "$package_name" "$package_name"
    printf 'su -s /bin/sh lxc_on_dsm -c '"'"'/var/packages/%s/scripts/start-stop-status status; echo status_exit=$?'"'"'\n' "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' '## Package lifecycle gate'
    printf '\n'
    printf '%s\n' 'Package `status` is expected to work as the package user. Package `start` is expected to fail fast with an explanatory root-lifecycle message.'
    printf '\n'
    printf '```sh\n'
    printf '/usr/syno/bin/synopkg status %s\n' "$package_name"
    printf '/usr/syno/bin/synopkg start %s\n' "$package_name"
    printf '/usr/syno/bin/synopkg status %s\n' "$package_name"
    printf 'find /var/packages/%s/var/artifacts -maxdepth 1 -type f | sort\n' "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' 'Manual root lifecycle smoke test, only after reviewing the package start blocker and confirming the lab state is clean:'
    printf '\n'
    printf '```sh\n'
    printf 'sh /var/packages/%s/scripts/start-stop-status start\n' "$package_name"
    printf 'sh /var/packages/%s/target/scripts/doctor-macvlan-profile.sh --profile /var/packages/%s/etc/lab-macvlan.env\n' "$package_name" "$package_name"
    printf 'sh /var/packages/%s/scripts/start-stop-status stop\n' "$package_name"
    printf 'sh /var/packages/%s/target/scripts/doctor-macvlan-profile.sh --profile /var/packages/%s/etc/lab-macvlan.env\n' "$package_name" "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' 'Expected post-stop doctor state: container stopped, no runtime state, no shim and no lifecycle route.'
    printf '\n'
    printf '%s\n' '## Rollback / uninstall'
    printf '\n'
    printf '%s\n' 'Only after confirming the package is stopped:'
    printf '\n'
    printf '```sh\n'
    printf '/usr/syno/bin/synopkg stop %s\n' "$package_name"
    printf 'sh /var/packages/%s/target/scripts/doctor-macvlan-profile.sh --profile /var/packages/%s/etc/lab-macvlan.env\n' "$package_name" "$package_name"
    printf '/usr/syno/bin/synopkg uninstall %s\n' "$package_name"
    printf '```\n'
    printf '\n'
    printf '%s\n' 'If any lifecycle-owned shim or route remains, do not uninstall blindly; inspect before manual cleanup.'
    printf '\n'
    printf '%s\n' 'Result: SPK INSTALL PLAN GENERATED. No package was installed and no package scripts were executed.'
} >"$plan_file"

cat "$plan_file"
