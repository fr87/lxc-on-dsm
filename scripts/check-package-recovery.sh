#!/bin/sh
# Read-only check for installed DSM package recovery / repair readiness.
# Does not install packages, start/stop containers or change networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--package NAME] [--expected-version VERSION] [--profile FILE] [--output DIRECTORY]"
}

package_name=lxc-on-dsm
expected_version=0.1.0-0010
profile_file=/var/packages/lxc-on-dsm/etc/lab-macvlan.env
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --expected-version) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; expected_version=$2; shift 2 ;;
        --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile_file=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
case "$expected_version" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid expected version: %s\n' "$expected_version" >&2; exit 2 ;; esac

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
report_file="${output_dir}/package-recovery-${package_name}-${stamp}.md"

base="/var/packages/${package_name}"
target="${base}/target"
etc_dir="${base}/etc"
var_dir="${base}/var"
conf_dir="${base}/conf"
info_file="${base}/INFO"
privilege_file="${conf_dir}/privilege"
wrapper="${base}/scripts/start-stop-status"
helper="${target}/scripts/lxc-on-dsm-root-helper.sh"

problems=0
warnings=0

ok() {
    printf 'OK: %s\n' "$1"
}

warn() {
    warnings=$((warnings + 1))
    printf 'WARN: %s\n' "$1"
}

problem() {
    problems=$((problems + 1))
    printf 'PROBLEM: %s\n' "$1"
}

{
    printf '%s\n' '# DSM package recovery check'
    printf '\n'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'package=%s\n' "$package_name"
    printf 'expected_version=%s\n' "$expected_version"
    printf 'profile=%s\n' "$profile_file"
    printf '\n'
    printf '%s\n' '## Scope'
    printf '\n'
    printf '%s\n' '- read-only'
    printf '%s\n' '- does not install, repair, start or stop the package'
    printf '%s\n' '- does not start or stop containers'
    printf '%s\n' '- does not create interfaces, routes, bridges or firewall rules'
    printf '\n'
    printf '%s\n' '## Installed package files'
    printf '\n'

    [ -d "$base" ] && ok "package directory exists: $base" || problem "package directory missing: $base"
    [ -r "$info_file" ] && ok "INFO is readable" || problem "INFO missing: $info_file"
    if [ -r "$info_file" ]; then
        installed_version=$(sed -n 's/^version="//p' "$info_file" | sed 's/"$//' | sed -n '1p')
        printf 'installed_version=%s\n' "$installed_version"
        [ "$installed_version" = "$expected_version" ] && ok "installed version matches expected" || problem "installed version mismatch: expected $expected_version got $installed_version"
    fi

    [ -r "$privilege_file" ] && ok "conf/privilege is readable" || problem "conf/privilege missing: $privilege_file"
    if [ -r "$privilege_file" ]; then
        grep -q '"run-as": "package"' "$privilege_file" && ok "package runs as package user" || problem "privilege does not declare run-as package"
        grep -q '"ctrl-script"' "$privilege_file" && problem "privilege contains ctrl-script attribute rewrite" || ok "privilege avoids ctrl-script attribute rewrites"
        grep -q '"tool"' "$privilege_file" && problem "privilege contains tool attribute rewrite" || ok "privilege avoids tool attribute rewrites"
    fi

    [ -x "$helper" ] && ok "installed root helper exists and is executable" || problem "installed root helper missing or not executable: $helper"
    if [ -e "$helper" ]; then
        helper_mode=$(ls -l "$helper" 2>/dev/null | awk '{ print $1 }' | sed -n '1p')
        printf 'helper_mode=%s\n' "$helper_mode"
        case "$helper_mode" in
            *s*) problem "installed helper appears to have setuid/setgid mode: $helper_mode" ;;
            -rwxr-xr-x) ok "installed helper is executable without setuid" ;;
            *) warn "installed helper has non-standard mode: $helper_mode" ;;
        esac
    fi

    [ -r "$wrapper" ] && ok "Package Center wrapper is readable" || problem "Package Center wrapper missing: $wrapper"
    if [ -r "$wrapper" ]; then
        grep -q 'requires root on DSM' "$wrapper" && ok "wrapper explains root lifecycle gate" || problem "wrapper does not explain root lifecycle gate"
        grep -q 'lxc-on-dsm-root-helper.sh' "$wrapper" && ok "wrapper points to installed helper" || problem "wrapper does not point to installed helper"
    fi

    [ -r "$profile_file" ] && ok "profile is readable" || problem "profile missing or unreadable: $profile_file"
    [ -d "$etc_dir" ] && ok "package etc link resolves" || problem "package etc path missing: $etc_dir"
    [ -d "$var_dir" ] && ok "package var link resolves" || problem "package var path missing: $var_dir"
    [ -d "${var_dir}/artifacts" ] && ok "package artifact directory exists" || warn "package artifact directory missing: ${var_dir}/artifacts"

    printf '\n'
    printf '%s\n' '## Package manager file observations'
    printf '\n'
    if [ -e "${base}/startFailed" ]; then
        warn "Package Center startFailed marker is present; this is expected after the root lifecycle gate is tested"
    else
        ok "Package Center startFailed marker is absent"
    fi

    printf '\n'
    printf '%s\n' '## Helper dry-run observation'
    printf '\n'
    if [ -x "$helper" ]; then
        sh "$helper" --dry-run status --profile "$profile_file" 2>&1 || problem "installed helper dry-run status failed"
    fi

    printf '\n'
    printf '%s\n' '## Runtime doctor observation'
    printf '\n'
    if [ -x "$helper" ] && [ -r "$profile_file" ]; then
        sh "$helper" status --profile "$profile_file" 2>&1 || problem "installed helper status failed"
    fi

    printf '\n'
    if [ "$problems" -eq 0 ]; then
        printf 'Result: PACKAGE RECOVERY CHECK PASS'
        [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
        printf '. No package or runtime state was changed.\n'
    else
        printf 'Result: PACKAGE RECOVERY CHECK FOUND %s PROBLEM(S)' "$problems"
        [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
        printf '. No package or runtime state was changed.\n'
        exit 1
    fi
} | tee "$report_file"
