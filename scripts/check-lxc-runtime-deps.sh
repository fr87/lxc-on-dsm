#!/bin/sh
# Check whether an installed LXC runtime prefix is usable on this DSM host.
# Does not start containers or change files/networking.
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--prefix DIRECTORY] [--allow-opt-interpreter]"
}

prefix=/volume1/@lxc/lab/opt
allow_opt_interpreter=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --allow-opt-interpreter) allow_opt_interpreter=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$prefix" in
    /volume[0-9]*/@lxc/lab/opt) ;;
    *) printf 'Refusing unexpected LXC prefix: %s\n' "$prefix" >&2; exit 2 ;;
esac

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

detect_interpreter() {
    binary=$1
    if command -v readelf >/dev/null 2>&1; then
        interpreter=$(readelf -l "$binary" 2>/dev/null | sed -n 's/.*interpreter: \([^]]*\).*/\1/p' | sed -n '1p')
        [ -n "$interpreter" ] && { printf '%s\n' "$interpreter"; return; }
        interpreter=$(readelf -l "$binary" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \([^]]*\).*/\1/p' | sed -n '1p')
        [ -n "$interpreter" ] && { printf '%s\n' "$interpreter"; return; }
    elif command -v file >/dev/null 2>&1; then
        file "$binary" 2>/dev/null | sed -n 's/.*interpreter \([^,]*\).*/\1/p' | sed -n '1p'
    else
        printf '%s\n' unknown
    fi
}

printf '%s\n' '# LXC runtime dependency check'
printf '\n'
printf 'prefix=%s\n' "$prefix"
printf 'allow_opt_interpreter=%s\n' "$allow_opt_interpreter"
printf '\n'

if [ -d "$prefix" ]; then
    ok "runtime prefix exists"
else
    problem "runtime prefix missing: $prefix"
fi

printf '\n'
printf '%s\n' '## Host runtime signals'
printf '\n'

if [ -e /opt ]; then
    ok "/opt exists"
else
    warn "/opt is absent"
fi

if [ -r /opt/lib/ld-linux-x86-64.so.2 ]; then
    ok "/opt Entware-style dynamic loader is present"
else
    warn "/opt Entware-style dynamic loader is absent"
fi

if [ -x /lib64/ld-linux-x86-64.so.2 ] || [ -x /lib/ld-linux-x86-64.so.2 ]; then
    ok "DSM system dynamic loader is present"
else
    warn "DSM system dynamic loader was not observed"
fi

printf '\n'
printf '%s\n' '## LXC binary interpreters'
printf '\n'

for binary in lxc-start lxc-info lxc-ls lxc-stop lxc-checkconfig; do
    path="${prefix}/bin/${binary}"
    if [ ! -r "$path" ]; then
        problem "missing LXC binary: $path"
        continue
    fi
    interpreter=$(detect_interpreter "$path")
    printf '%s_interpreter=%s\n' "$binary" "$interpreter"
    case "$interpreter" in
        /opt/*)
            if [ "$allow_opt_interpreter" -eq 1 ]; then
                warn "${binary} uses /opt interpreter; allowed for this check"
            else
                problem "${binary} depends on /opt interpreter: $interpreter"
            fi
            ;;
        /lib/*|/lib64/*)
            ok "${binary} uses DSM system interpreter: $interpreter"
            ;;
        unknown|'')
            warn "${binary} interpreter could not be determined"
            ;;
        *)
            warn "${binary} uses unexpected interpreter: $interpreter"
            ;;
    esac
done

printf '\n'
printf '%s\n' '## Direct version probe'
printf '\n'

PATH="${prefix}/bin:${prefix}/sbin:/usr/syno/bin:/bin:/sbin:/usr/bin:/usr/sbin"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

if lxc-start --version >/tmp/lxc-on-dsm-runtime-version.$$ 2>&1; then
    version=$(sed -n '1p' /tmp/lxc-on-dsm-runtime-version.$$)
    ok "lxc-start runs: ${version}"
else
    cat /tmp/lxc-on-dsm-runtime-version.$$
    problem "lxc-start cannot run on this host"
fi
rm -f /tmp/lxc-on-dsm-runtime-version.$$

printf '\n'
if [ "$problems" -eq 0 ]; then
    printf 'Result: LXC RUNTIME DEPENDENCY CHECK PASS'
    [ "$warnings" -eq 0 ] || printf ' WITH %s WARNING(S)' "$warnings"
    printf '. No container was started.\n'
else
    printf 'Result: LXC RUNTIME DEPENDENCY CHECK BLOCKED: %s PROBLEM(S)' "$problems"
    [ "$warnings" -eq 0 ] || printf ' AND %s WARNING(S)' "$warnings"
    printf '. Do not start containers with this runtime on this host.\n'
    exit 1
fi
