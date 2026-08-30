#!/bin/sh
# Guided package-owned HTTP example service test.
# Dry-run by default. Creates a fresh container only with --run.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --name NAME [--package NAME] [--prefix DIRECTORY] [--state-dir DIRECTORY] [--output DIRECTORY] [--network-type empty|macvlan] [--parent-if IFACE] [--run] [--remove-after-test]"
}

package_name=lxc-on-dsm
prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
output_dir=
name=
network_type=empty
parent_if=eth0
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
case "$network_type" in empty|macvlan) ;; *) printf 'Unsupported HTTP example network type: %s\n' "$network_type" >&2; exit 2 ;; esac
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
    [ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged HTTP example test requires uid=0.' >&2; exit 1; }
fi

create_container="${pkg_target}/scripts/create-packaged-container.sh"
install_hook="${pkg_target}/scripts/install-packaged-start-hook.sh"
install_snippet="${pkg_target}/scripts/install-packaged-hook-snippet.sh"
start_container="${pkg_target}/scripts/start-packaged-container.sh"
stop_container="${pkg_target}/scripts/stop-packaged-container.sh"
remove_container="${pkg_target}/scripts/remove-packaged-container.sh"
snippet_source="${pkg_target}/hooks/httpd.example.sh"

for script in "$create_container" "$install_hook" "$install_snippet" "$start_container" "$stop_container" "$remove_container"; do
    [ -r "$script" ] || { printf 'Missing packaged script: %s\n' "$script" >&2; exit 1; }
done
[ -r "$snippet_source" ] || { printf 'Missing packaged HTTP example snippet: %s\n' "$snippet_source" >&2; exit 1; }

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
evidence_file="${rootfs_dir}/tmp/lxc-on-dsm-httpd-example.env"

printf '%s\n' '# Packaged LXC HTTP example test plan'
printf '\n'
printf 'package=%s\n' "$package_name"
printf 'run=%s\n' "$run"
printf 'remove_after_test=%s\n' "$remove_after_test"
printf 'container=%s\n' "$name"
printf 'network_type=%s\n' "$network_type"
[ "$network_type" != macvlan ] || printf 'parent_if=%s\n' "$parent_if"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'snippet_source=%s\n' "$snippet_source"
printf 'evidence=%s\n' "$evidence_file"
printf 'output=%s\n' "$output_dir"
printf '\n'

if [ "$run" -ne 1 ]; then
    printf '%s\n' 'Result: PACKAGED HTTP EXAMPLE TEST DRY RUN COMPLETE. No container was created, no service was started, and no networking was changed.'
    exit 0
fi

[ ! -e "$container_dir" ] || { printf 'Container already exists, choose a fresh test name: %s\n' "$container_dir" >&2; exit 1; }
[ -x "${prefix}/bin/lxc-start" ] || { printf 'Missing runtime lxc-start under prefix: %s\n' "$prefix" >&2; exit 1; }

if [ "$network_type" = macvlan ]; then
    sh "$create_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --network-type macvlan --parent-if "$parent_if" --create
else
    sh "$create_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --network-type empty --create
fi

sh "$install_hook" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --install
sh "$install_snippet" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --snippet 20-httpd --source "$snippet_source" --install
sh "$start_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir" --run

i=0
while [ "$i" -lt 10 ]; do
    [ -r "$evidence_file" ] && break
    i=$((i + 1))
    sleep 1
done

[ -r "$evidence_file" ] || { printf 'HTTP example evidence missing: %s\n' "$evidence_file" >&2; sh "$stop_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir" || true; exit 1; }
status=$(sed -n 's/^status=//p' "$evidence_file" | sed -n '1p')
port=$(sed -n 's/^port=//p' "$evidence_file" | sed -n '1p')
reason=$(sed -n 's/^reason=//p' "$evidence_file" | sed -n '1p')

if [ "$status" != STARTED ]; then
    printf 'HTTP example service did not start: status=%s reason=%s\n' "$status" "$reason" >&2
    sh "$stop_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir" || true
    exit 1
fi

runtime_state="${container_dir}/packaged-start-state.env"
container_ip=
if [ -r "$runtime_state" ]; then
    container_ip=$(sed -n 's/^container_ip=//p' "$runtime_state" | sed -n '1p')
fi

http_fetch=SKIPPED
if [ "$network_type" = macvlan ] && [ -n "$container_ip" ]; then
    if command -v curl >/dev/null 2>&1; then
        curl -fsS "http://${container_ip}:${port}/" >/dev/null 2>&1 && http_fetch=OK || http_fetch=FAIL
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O - "http://${container_ip}:${port}/" >/dev/null 2>&1 && http_fetch=OK || http_fetch=FAIL
    else
        http_fetch=NO_FETCH_TOOL
    fi
fi

sh "$stop_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir"

if [ "$remove_after_test" -eq 1 ]; then
    sh "$remove_container" --name "$name" --prefix "$prefix" --state-dir "$state_dir" --output "$output_dir" --backup --destroy
fi

printf '%s\n' '# Packaged LXC HTTP example test summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'network_type=%s\n' "$network_type"
printf 'service_status=%s\n' "$status"
printf 'service_port=%s\n' "$port"
printf 'container_ip=%s\n' "$container_ip"
printf 'http_fetch=%s\n' "$http_fetch"
printf 'removed_after_test=%s\n' "$remove_after_test"
printf '\n'
printf '%s\n' 'Result: PACKAGED HTTP EXAMPLE TEST PASSED. Example service was started through the container start hook.'
