#!/bin/sh
# Experimental non-installed root helper prototype for lxc-on-dsm.
# This script is not copied into the DSM package payload.
set -eu

PACKAGE=lxc-on-dsm
BASE="/var/packages/${PACKAGE}"
TARGET="${BASE}/target"
PROFILE_DEFAULT="${BASE}/etc/lab-macvlan.env"
OUTPUT_DEFAULT="${BASE}/var/artifacts"

usage() {
    printf '%s\n' "Usage: $0 [--dry-run] [--profile FILE] [--output DIRECTORY] {start|stop|status}"
}

dry_run=0
profile_file=$PROFILE_DEFAULT
output_dir=$OUTPUT_DEFAULT
verb=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1; shift ;;
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        start|stop|status)
            [ -z "$verb" ] || { printf 'Only one verb is allowed\n' >&2; exit 2; }
            verb=$1
            shift
            ;;
        *) printf 'Unknown argument or verb: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$verb" ] || { usage >&2; exit 2; }

case "$profile_file" in
    "${BASE}/etc/"*) ;;
    *) printf 'Profile must be under %s/etc/: %s\n' "$BASE" "$profile_file" >&2; exit 2 ;;
esac
case "$profile_file" in
    *'/../'*|*'/..'|'../'*|*'/.'|*'//'*) printf 'Unsafe profile path: %s\n' "$profile_file" >&2; exit 2 ;;
esac
case "$output_dir" in
    "${BASE}/var/artifacts"| "${BASE}/var/artifacts/"*) ;;
    *) printf 'Output directory must be under %s/var/artifacts: %s\n' "$BASE" "$output_dir" >&2; exit 2 ;;
esac
case "$output_dir" in
    *'/../'*|*'/..'|'../'*|*'/.'|*'//'*) printf 'Unsafe output path: %s\n' "$output_dir" >&2; exit 2 ;;
esac

case "$verb" in
    start) target_script="${TARGET}/scripts/start-macvlan-profile.sh" ;;
    stop) target_script="${TARGET}/scripts/stop-macvlan-profile.sh" ;;
    status) target_script="${TARGET}/scripts/doctor-macvlan-profile.sh" ;;
    *) printf 'Unsupported verb: %s\n' "$verb" >&2; exit 2 ;;
esac

if [ "$dry_run" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' 'Root helper real execution requires uid=0.' >&2
    exit 1
fi

if [ "$dry_run" -ne 1 ]; then
    [ -r "$profile_file" ] || { printf 'Missing profile: %s\n' "$profile_file" >&2; exit 1; }
    [ -x "$target_script" ] || { printf 'Missing target script: %s\n' "$target_script" >&2; exit 1; }
    mkdir -p "$output_dir"
fi

if [ -r "$profile_file" ]; then
    # shellcheck disable=SC1090
    . "$profile_file"

    prefix=${LXC_LAB_PREFIX:-}
    state_dir=${LXC_LAB_STATE_DIR:-}
    name=${LXC_LAB_CONTAINER:-}
    parent_if=${LXC_LAB_PARENT_IF:-}
    shim_if=${LXC_LAB_SHIM_IF:-}

    [ -n "$prefix" ] || { printf 'Profile missing LXC_LAB_PREFIX\n' >&2; exit 1; }
    [ -n "$state_dir" ] || { printf 'Profile missing LXC_LAB_STATE_DIR\n' >&2; exit 1; }
    [ -n "$name" ] || { printf 'Profile missing LXC_LAB_CONTAINER\n' >&2; exit 1; }
    [ -n "$parent_if" ] || { printf 'Profile missing LXC_LAB_PARENT_IF\n' >&2; exit 1; }
    [ -n "$shim_if" ] || { printf 'Profile missing LXC_LAB_SHIM_IF\n' >&2; exit 1; }

    case "$prefix" in /volume[0-9]*/@lxc/lab/opt) ;; *) printf 'Unexpected LXC prefix: %s\n' "$prefix" >&2; exit 1 ;; esac
    case "$state_dir" in /volume[0-9]*/@lxc/lab/containers) ;; *) printf 'Unexpected state dir: %s\n' "$state_dir" >&2; exit 1 ;; esac
    case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 1 ;; esac
    case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface: %s\n' "$parent_if" >&2; exit 1 ;; esac
    case "$shim_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid shim interface: %s\n' "$shim_if" >&2; exit 1 ;; esac
else
    prefix=UNKNOWN
    state_dir=UNKNOWN
    name=UNKNOWN
    parent_if=UNKNOWN
    shim_if=UNKNOWN
fi

printf '%s\n' '# lxc-on-dsm root helper prototype'
printf '\n'
printf 'package=%s\n' "$PACKAGE"
printf 'verb=%s\n' "$verb"
printf 'dry_run=%s\n' "$dry_run"
printf 'profile=%s\n' "$profile_file"
printf 'output=%s\n' "$output_dir"
printf 'target_script=%s\n' "$target_script"
printf 'container=%s\n' "$name"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'parent_if=%s\n' "$parent_if"
printf 'shim_if=%s\n' "$shim_if"
printf '\n'

if [ "$dry_run" -eq 1 ]; then
    printf '%s\n' 'Result: ROOT HELPER DRY RUN COMPLETE. No lifecycle action was executed.'
    exit 0
fi

case "$verb" in
    start|stop)
        exec sh "$target_script" --profile "$profile_file" --output "$output_dir"
        ;;
    status)
        exec sh "$target_script" --profile "$profile_file"
        ;;
esac
