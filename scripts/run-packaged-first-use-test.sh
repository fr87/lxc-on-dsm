#!/bin/sh
# Guided first-use validation for an installed lxc-on-dsm package.
# Dry-run by default. Uses only packaged scripts and explicit flags.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --name NAME [--package NAME] [--prefix DIRECTORY] [--state-dir DIRECTORY] [--output DIRECTORY] [--network-type none|empty|macvlan] [--parent-if IFACE] [--restore-runtime] [--run] [--remove-after-test]"
}

package_name=lxc-on-dsm
prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
output_dir=
name=
network_type=empty
parent_if=eth0
restore_runtime=0
run=0
remove_after_test=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --package) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; package_name=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --network-type) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; network_type=$2; shift 2 ;;
        --parent-if) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; parent_if=$2; shift 2 ;;
        --restore-runtime) restore_runtime=1; shift ;;
        --run) run=1; shift ;;
        --remove-after-test) remove_after_test=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$name" ] || { usage >&2; exit 2; }
case "$package_name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid package name: %s\n' "$package_name" >&2; exit 2 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac
case "$prefix" in /volume[0-9]*/@lxc/lab/opt) ;; *) printf 'Unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /volume[0-9]*/@lxc/lab/containers) ;; *) printf 'Unexpected state dir: %s\n' "$state_dir" >&2; exit 2 ;; esac
case "$network_type" in none|empty|macvlan) ;; *) printf 'Unsupported network type: %s\n' "$network_type" >&2; exit 2 ;; esac
case "$parent_if" in *[!A-Za-z0-9_.:-]*|'') printf 'Invalid parent interface: %s\n' "$parent_if" >&2; exit 2 ;; esac
if [ ${#parent_if} -gt 15 ]; then
    printf 'Parent interface name is too long for Linux interfaces: %s\n' "$parent_if" >&2
    exit 2
fi

pkg_base="/var/packages/${package_name}"
pkg_target="${pkg_base}/target"
pkg_var="${pkg_base}/var"
[ -n "$output_dir" ] || output_dir="${pkg_var}/artifacts"
case "$output_dir" in
    /var/packages/"${package_name}"/var/artifacts|/volume[0-9]*/@appdata/"${package_name}"/artifacts|artifacts|artifacts/*) ;;
    *) printf 'Unexpected output directory: %s\n' "$output_dir" >&2; exit 2 ;;
esac

if [ "$run" -eq 1 ]; then
    [ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged first-use test requires uid=0.' >&2; exit 1; }
fi

install_runtime="${pkg_target}/scripts/install-packaged-runtime.sh"
create_container="${pkg_target}/scripts/create-packaged-container.sh"
smoke_test="${pkg_target}/scripts/run-packaged-smoke-test.sh"
start_container="${pkg_target}/scripts/start-packaged-container.sh"
stop_container="${pkg_target}/scripts/stop-packaged-container.sh"
remove_container="${pkg_target}/scripts/remove-packaged-container.sh"
macvlan_test="${pkg_target}/scripts/run-packaged-macvlan-dhcp-test.sh"
inventory="${pkg_target}/scripts/list-packaged-containers.sh"

for script in "$create_container" "$remove_container" "$inventory"; do
    [ -r "$script" ] || { printf 'Missing packaged script: %s\n' "$script" >&2; exit 1; }
done
[ "$restore_runtime" -eq 0 ] || [ -r "$install_runtime" ] || { printf 'Missing packaged runtime installer: %s\n' "$install_runtime" >&2; exit 1; }
case "$network_type" in
    none) [ -r "$smoke_test" ] || { printf 'Missing packaged smoke test: %s\n' "$smoke_test" >&2; exit 1; } ;;
    empty) [ -r "$start_container" ] && [ -r "$stop_container" ] || { printf '%s\n' 'Missing packaged empty lifecycle scripts' >&2; exit 1; } ;;
    macvlan) [ -r "$macvlan_test" ] || { printf 'Missing packaged macvlan DHCP test: %s\n' "$macvlan_test" >&2; exit 1; } ;;
esac

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"

printf '%s\n' '# Packaged LXC first-use test plan'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'run=%s\n' "$run"
printf 'restore_runtime=%s\n' "$restore_runtime"
printf 'remove_after_test=%s\n' "$remove_after_test"
printf 'container=%s\n' "$name"
printf 'network_type=%s\n' "$network_type"
[ "$network_type" != macvlan ] || printf 'parent_if=%s\n' "$parent_if"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'output=%s\n' "$output_dir"
printf '\n'
printf '%s\n' 'Planned packaged commands:'
[ "$restore_runtime" -eq 0 ] || printf 'sh %s --target %s --output %s --install\n' "$install_runtime" "$prefix" "$output_dir"
if [ "$network_type" = macvlan ]; then
    printf 'sh %s --name %s --prefix %s --state-dir %s --network-type macvlan --parent-if %s --create\n' "$create_container" "$name" "$prefix" "$state_dir" "$parent_if"
else
    printf 'sh %s --name %s --prefix %s --state-dir %s --network-type %s --create\n' "$create_container" "$name" "$prefix" "$state_dir" "$network_type"
fi
case "$network_type" in
    none) printf 'sh %s --name %s --prefix %s --state-dir %s --output %s\n' "$smoke_test" "$name" "$prefix" "$state_dir" "$output_dir" ;;
    empty)
        printf 'sh %s --name %s --prefix %s --state-dir %s --output %s --run\n' "$start_container" "$name" "$prefix" "$state_dir" "$output_dir"
        printf 'sh %s --name %s --prefix %s --state-dir %s --output %s\n' "$stop_container" "$name" "$prefix" "$state_dir" "$output_dir"
        ;;
    macvlan) printf 'sh %s --name %s --prefix %s --state-dir %s --output %s --run\n' "$macvlan_test" "$name" "$prefix" "$state_dir" "$output_dir" ;;
esac
[ "$remove_after_test" -eq 0 ] || printf 'sh %s --name %s --prefix %s --state-dir %s --output %s --backup --destroy\n' "$remove_container" "$name" "$prefix" "$state_dir" "$output_dir"
printf 'sh %s --prefix %s --state-dir %s\n' "$inventory" "$prefix" "$state_dir"
printf '\n'

if [ "$run" -ne 1 ]; then
    printf '%s\n' 'Result: PACKAGED FIRST USE TEST DRY RUN COMPLETE. No runtime files were restored, no container was created, and no networking was changed.'
    exit 0
fi

[ ! -e "$container_dir" ] || { printf 'Container already exists, choose a fresh test name: %s\n' "$container_dir" >&2; exit 1; }

if [ "$restore_runtime" -eq 1 ]; then
    sh "$install_runtime" --target "$prefix" --output "$output_dir" --install
fi

[ -x "${prefix}/bin/lxc-start" ] || { printf 'Missing runtime lxc-start under prefix: %s\n' "$prefix" >&2; exit 1; }

if [ "$network_type" = macvlan ]; then
    sh "$create_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --network-type macvlan --parent-if "$parent_if" --create
else
    sh "$create_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --network-type "$network_type" --create
fi

[ -r "$config_file" ] || { printf 'Container config was not created: %s\n' "$config_file" >&2; exit 1; }

case "$network_type" in
    none)
        sh "$smoke_test" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir"
        ;;
    empty)
        sh "$start_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir" --run
        sh "$stop_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir"
        ;;
    macvlan)
        sh "$macvlan_test" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir" --run
        ;;
esac

if [ "$remove_after_test" -eq 1 ]; then
    sh "$remove_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir" --backup --destroy
fi

sh "$inventory" --prefix "$prefix" --state-dir "$state_dir"

printf '\nResult: PACKAGED FIRST USE TEST PASSED. Reviewed packaged commands completed successfully.\n'
