#!/bin/sh
# Install the lxc-on-dsm in-container start hook into a stopped lab container.
# Dry-run by default. Does not start containers or change networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --name NAME [--prefix DIRECTORY] [--state-dir DIRECTORY] [--install] [--force]"
}

prefix=/volume1/@lxc/lab/opt
state_dir=/volume1/@lxc/lab/containers
name=
install=0
force=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --install) install=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$name" ] || { usage >&2; exit 2; }
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac
case "$prefix" in /volume[0-9]*/@lxc/lab/opt) ;; *) printf 'Unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /volume[0-9]*/@lxc/lab/containers) ;; *) printf 'Unexpected state dir: %s\n' "$state_dir" >&2; exit 2 ;; esac

PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib:${prefix}/lib64:${LD_LIBRARY_PATH:-}"
LXC_CONFIG_PATH="$state_dir"
export PATH LD_LIBRARY_PATH LXC_CONFIG_PATH

container_dir="${state_dir}/${name}"
rootfs_dir="${container_dir}/rootfs"
config_file="${container_dir}/config"
hook_dir="${rootfs_dir}/etc/lxc-on-dsm"
start_d="${hook_dir}/start.d"
hook_file="${hook_dir}/start.sh"

[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
[ -d "$rootfs_dir" ] || { printf 'Missing rootfs: %s\n' "$rootfs_dir" >&2; exit 1; }

if command -v lxc-info >/dev/null 2>&1 && lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is running, refusing to modify rootfs hook: %s\n' "$name" >&2
    exit 1
fi

printf '%s\n' '# Packaged LXC start hook install plan'
printf '\n'
printf 'container=%s\n' "$name"
printf 'prefix=%s\n' "$prefix"
printf 'state_dir=%s\n' "$state_dir"
printf 'rootfs=%s\n' "$rootfs_dir"
printf 'hook_file=%s\n' "$hook_file"
printf 'start_d=%s\n' "$start_d"
printf 'install=%s\n' "$install"
printf 'force=%s\n' "$force"
printf '\n'

if [ "$install" -ne 1 ]; then
    [ ! -e "$hook_file" ] || printf 'WARN: hook file already exists: %s\n' "$hook_file"
    printf '%s\n' 'Result: PACKAGED START HOOK INSTALL DRY RUN COMPLETE. No files were written and no container was started.'
    exit 0
fi

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Packaged start hook install requires uid=0.' >&2; exit 1; }
if [ -e "$hook_file" ] && [ "$force" -ne 1 ]; then
    printf 'Hook file already exists; use --force to replace: %s\n' "$hook_file" >&2
    exit 1
fi

mkdir -p "$start_d"
cat >"$hook_file" <<'EOF'
#!/bin/sh
# lxc-on-dsm container start hook dispatcher.
set -eu

log_file=/var/log/lxc-on-dsm-start.log
mkdir -p /var/log
{
    printf 'lxc-on-dsm start hook begin: %s\n' "$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
    if [ -d /etc/lxc-on-dsm/start.d ]; then
        for hook in /etc/lxc-on-dsm/start.d/*.sh; do
            [ -e "$hook" ] || continue
            if [ -x "$hook" ]; then
                printf 'running %s\n' "$hook"
                "$hook"
            else
                printf 'skipping non-executable %s\n' "$hook"
            fi
        done
    fi
    printf 'lxc-on-dsm start hook end\n'
} >>"$log_file" 2>&1
EOF
chmod 0755 "$hook_file"
chmod 0755 "$hook_dir" "$start_d"

printf '%s\n' '# Packaged LXC start hook install summary'
printf '\n'
printf 'container=%s\n' "$name"
printf 'hook_file=%s\n' "$hook_file"
printf 'start_d=%s\n' "$start_d"
printf '\n'
printf '%s\n' 'Result: PACKAGED START HOOK INSTALLED. No container was started and no networking was changed.'
