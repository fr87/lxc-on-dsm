#!/bin/sh
# Fetch pinned Phase 2 source tarballs. Writes only beneath --output.
set -eu
PATH="/opt/bin:/opt/sbin:${PATH}"

usage() { printf '%s\n' "Usage: $0 [--manifest FILE] [--output DIRECTORY] [--gpg-home DIRECTORY]"; }
manifest=manifests/lxc-userspace.env
output_dir="${PWD}/build/sources"
gpg_home=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --manifest) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; manifest=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        --gpg-home) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; gpg_home=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -r "$manifest" ] || { printf 'Missing manifest: %s\n' "$manifest" >&2; exit 2; }
. "$manifest"
mkdir -p "$output_dir"
[ -n "$gpg_home" ] || gpg_home="${output_dir}/gnupg"

download() {
    url=$1
    destination=$2
    if [ -f "$destination" ]; then
        printf 'OK: already present: %s\n' "$destination"
        return
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fL "$url" -o "$destination"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$destination" "$url"
    else
        printf 'Missing downloader: curl or wget required\n' >&2
        exit 1
    fi
}

verify_sha256() {
    file=$1
    expected=$2
    if [ "$expected" = TODO ]; then
        printf 'WARN: no pinned sha256 for %s yet\n' "$file"
        if command -v sha256sum >/dev/null 2>&1; then
            actual=$(sha256sum "$file" | awk '{ print $1 }')
            printf 'PINNED_SHA256 %s %s\n' "$(basename "$file")" "$actual"
        fi
        return
    fi
    if ! command -v sha256sum >/dev/null 2>&1; then
        printf 'WARN: sha256sum unavailable; skipped %s\n' "$file"
        return
    fi
    actual=$(sha256sum "$file" | awk '{ print $1 }')
    [ "$actual" = "$expected" ] || {
        printf 'SHA256 mismatch for %s\nexpected=%s\nactual=%s\n' "$file" "$expected" "$actual" >&2
        exit 1
    }
    printf 'OK: sha256 verified: %s\n' "$file"
}

verify_signature() {
    file=$1
    signature=$2
    if command -v gpg >/dev/null 2>&1; then
        mkdir -p "$gpg_home"
        chmod 700 "$gpg_home" 2>/dev/null || true
        gpg --homedir "$gpg_home" --verify "$signature" "$file" || {
            printf 'WARN: gpg verification failed or maintainer key is missing: %s\n' "$file"
            return
        }
        printf 'OK: gpg signature verified: %s\n' "$file"
    else
        printf 'WARN: gpg unavailable; skipped signature verification for %s\n' "$file"
    fi
}

lxc_tar="${output_dir}/lxc-${LXC_VERSION}.tar.gz"
lxc_asc="${lxc_tar}.asc"
lxcfs_tar="${output_dir}/lxcfs-${LXCFS_VERSION}.tar.gz"
lxcfs_asc="${lxcfs_tar}.asc"

download "$LXC_URL" "$lxc_tar"
download "$LXC_ASC_URL" "$lxc_asc"
download "$LXCFS_URL" "$lxcfs_tar"
download "$LXCFS_ASC_URL" "$lxcfs_asc"

verify_sha256 "$lxc_tar" "$LXC_SHA256"
verify_sha256 "$lxcfs_tar" "$LXCFS_SHA256"
verify_signature "$lxc_tar" "$lxc_asc"
verify_signature "$lxcfs_tar" "$lxcfs_asc"

printf 'Sources ready in %s\n' "$output_dir"
