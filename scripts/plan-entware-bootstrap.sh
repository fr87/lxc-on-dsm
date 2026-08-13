#!/bin/sh
# Print a Virtual DSM Entware bootstrap plan. Does not modify the system.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--volume /volume1] [--output FILE]"
}

volume=/volume1
output_file=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --volume) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; volume=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_file=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$volume" in
    /volume*) ;;
    *) printf 'Refusing non-volume target: %s\n' "$volume" >&2; exit 2 ;;
esac

arch=$(uname -m 2>/dev/null || printf unknown)
case "$arch" in
    x86_64) entware_arch=x64-k3.2 ;;
    aarch64) entware_arch=aarch64-k3.10 ;;
    armv7l|armv7*) entware_arch=armv7sf-k3.2 ;;
    *) entware_arch=unknown ;;
esac

[ "$entware_arch" != unknown ] || {
    printf 'Unsupported or unknown architecture for Entware bootstrap planning: %s\n' "$arch" >&2
    exit 1
}

entware_root="${volume}/@Entware/opt"
installer_url="https://bin.entware.net/${entware_arch}/installer/generic.sh"

emit() {
    if [ -n "$output_file" ]; then
        printf '%s\n' "$*" | tee -a "$output_file"
    else
        printf '%s\n' "$*"
    fi
}

if [ -n "$output_file" ]; then
    : >"$output_file"
fi

emit "# Virtual DSM Entware bootstrap plan"
emit ""
emit "architecture=${arch}"
emit "entware_arch=${entware_arch}"
emit "entware_root=${entware_root}"
emit "installer_url=${installer_url}"
emit ""
emit "## Manual commands"
emit ""
emit "Run these only inside the Virtual DSM lab system, as root:"
emit ""
emit '```sh'
emit "mkdir -p ${entware_root}"
emit 'if [ -e /opt ] && [ ! -d /opt ]; then echo "/opt exists but is not a directory" >&2; exit 1; fi'
emit 'mkdir -p /opt'
emit "mount -o bind \"${entware_root}\" /opt"
emit "curl -fL \"${installer_url}\" | /bin/sh"
emit '. /opt/etc/profile'
emit 'opkg update'
emit 'opkg install gcc binutils busybox gawk ldd make sed tar'
emit 'opkg install coreutils-install diffutils ldconfig patch pkgconf --force-overwrite'
emit 'opkg install bash git python3-pip python3-setuptools'
emit 'python3 -m pip install -U wheel meson'
emit '```'
emit ""
emit "If no Entware ninja package exists, build Ninja after the package step:"
emit ""
emit '```sh'
emit 'mkdir -p /opt/tmp'
emit 'cd /opt/tmp'
emit 'git clone https://github.com/ninja-build/ninja.git'
emit 'cd ninja'
emit 'git checkout release'
emit 'CONFIG_SHELL=/opt/bin/bash python3 ./configure.py --bootstrap'
emit 'install -Dm0755 -t /opt/bin ./ninja'
emit 'cd /opt/tmp'
emit 'rm -Rf /opt/tmp/ninja'
emit '```'
emit ""
emit "Afterwards, rerun:"
emit ""
emit '```sh'
emit 'sh scripts/check-phase2-prereqs.sh'
emit '```'
