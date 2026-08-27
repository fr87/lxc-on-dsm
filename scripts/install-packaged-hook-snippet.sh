#!/bin/sh
# Install one executable start.d snippet into a stopped package-created container.
# Dry-run by default. Does not start containers or change networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --name NAME --snippet NAME --source FILE [--prefix DIRECTORY] [--state-dir DIRECTORY] [--install] [--force]"
}

package_name=lxc-on-dsm
prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
name=
snippet=
source_file=
install=0
force=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --snippet) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; snippet=$2; shift 2 ;;
        --source) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; source_file=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --install) install=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$name" ] || { usage >&2; exit 2; }
[ -n "$snippet" ] || { usage >&2; exit 2; }
[ -n "$source_file" ] || { usage >&2; exit 2; }
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac
case "$snippet" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid snippet name: %s\n' "$snippet" >&2; exit 2 ;; esac
case "$snippet" in *.sh) ;; *) snippet="${snippet}.sh" ;; esac
case "$prefix" in /volume[0-9]*/@lxc/lab/opt) ;; *) printf 'Unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /volume[0-9]*/@lxc/lab/containers) ;; *) printf 'Unexpected state dir: %s\n' "$state_dir" >&2; exit 2 ;; esac
case "$source_file" in
    /var/packages/"${package_name}"/etc/hooks/*.sh|/var/packages/"${package_name}"/target/hooks/*.sh|/volume[0-9]*/@appconf/"${package_name}"/hooks/*.sh|/volume[0-9]*/@appstore/"${package_name}"/hooks/*.sh) ;;
    *) printf 'Unexpected hook snippet source path: %s\n' "$source_file" >&2; exit 2 ;;
esac

PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib:${prefix}/lib64:${LD_LIBRARY_PATH:-}"
LXC_CONFIG_PATH="$state_dir"
export PATH LD_LIBRARY_PATH LXC_CONFIG_PATH

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"
hook_file="${rootfs_dir}/etc/lxc-on-dsm/start.sh"
start_d="${rootfs_dir}/etc/lxc-on-dsm/start.d"
target_file="${start_d}/${snippet}"

[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }
[ -r "$source_file" ] || { printf 'Missing hook snippet source: %s\n' "$source_file" >&2; exit 1; }
[ -r "$hook_file" ] || { printf 'Missing hook dispatcher; install it first: %s\n' "$hook_file" >&2; exit 1; }

if command -v lxc-info >/dev/null 2>&1 && lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is running, refusing to modify hook snippets: %s\n' "$name" >&2
    exit 1
fi

printf '%s\n' '# Packaged LXC hook snippet install plan'
printf '\n'
printf 'container=%s\n' "$name"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'source=%s\n' "$source_file"
printf 'target=%s\n' "$target_file"
printf 'install=%s\n' "$install"
printf 'force=%s\n' "$force"
printf '\n'

if [ "$install" -ne 1 ]; then
    [ ! -e "$target_file" ] || printf 'WARN: target snippet already exists: %s\n' "$target_file"
    printf '%s\n' 'Result: PACKAGED HOOK SNIPPET INSTALL DRY RUN COMPLETE. No files were written and no container was started.'
    exit 0
fi

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged hook snippet install requires uid=0.' >&2; exit 1; }
if [ -e "$target_file" ] && [ "$force" -ne 1 ]; then
    printf 'Target snippet already exists; use --force to replace: %s\n' "$target_file" >&2
    exit 1
fi

mkdir -p "$start_d"
cp "$source_file" "$target_file"
chmod 0755 "$target_file"

printf '%s\n' '# Packaged LXC hook snippet install summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'source=%s\n' "$source_file"
printf 'target=%s\n' "$target_file"
printf '\n'
printf '%s\n' 'Result: PACKAGED HOOK SNIPPET INSTALLED. No container was started and no networking was changed.'
