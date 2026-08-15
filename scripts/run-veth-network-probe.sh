#!/bin/sh
# Probe veth lifecycle without attaching it to a bridge.
set -eu

usage() {
    printf '%s\n' "Usage: $0 --prefix DIRECTORY [--name NAME] [--state-dir DIRECTORY] [--output DIRECTORY]"
}

prefix=""
name=alpine-vethlab
state_dir=/volume1/@lxc/lab/containers
output_dir=artifacts

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; prefix=$2; shift 2 ;;
        --name) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
        --state-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; state_dir=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_dir=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { usage >&2; exit 2; }
case "$prefix" in /*) ;; *) printf 'Prefix must be absolute: %s\n' "$prefix" >&2; exit 2 ;; esac
case "$state_dir" in /*) ;; *) printf 'State dir must be absolute: %s\n' "$state_dir" >&2; exit 2 ;; esac
case "$name" in *[!A-Za-z0-9_.-]*|'') printf 'Invalid container name: %s\n' "$name" >&2; exit 2 ;; esac

PATH="${prefix}/bin:${prefix}/sbin:/opt/bin:/opt/sbin:${PATH}"
LD_LIBRARY_PATH="${prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH LD_LIBRARY_PATH

container_dir="${state_dir}/${name}"
config_file="${container_dir}/config"
[ -r "$config_file" ] || { printf 'Missing config: %s\n' "$config_file" >&2; exit 1; }
grep -q '^lxc\.net\.0\.type = veth$' "$config_file" || {
    printf 'Container is not configured for the veth gate: %s\n' "$config_file" >&2
    exit 1
}
command -v ip >/dev/null 2>&1 || { printf 'Missing ip command; cannot observe host veth lifecycle\n' >&2; exit 1; }

host_veth=$(sed -n 's/^lxc\.net\.0\.veth\.pair = //p' "$config_file" | sed -n '1p')
[ -n "$host_veth" ] || { printf 'Missing lxc.net.0.veth.pair in config: %s\n' "$config_file" >&2; exit 1; }
bridge_link=$(sed -n 's/^lxc\.net\.0\.link = //p' "$config_file" | sed -n '1p')
bridge_mode=0
if [ -n "$bridge_link" ]; then
    bridge_mode=1
fi

mkdir -p "$output_dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="${output_dir}/lxc-veth-${name}-${stamp}.log"
started=0

show_log_tail() {
    if [ -r "$log_file" ]; then
        printf '\nLast log lines from %s:\n' "$log_file" >&2
        tail -n 80 "$log_file" >&2 || true
    fi
}

fail_with_log() {
    printf '%s\n' "$1" >&2
    show_log_tail
    exit 1
}

cleanup() {
    if [ "$started" -eq 1 ] && lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
        lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
    fi
}
trap cleanup EXIT HUP INT TERM

host_link_exists() {
    ip link show "$host_veth" >/dev/null 2>&1
}

bridge_link_exists() {
    [ -n "$bridge_link" ] && ip link show "$bridge_link" >/dev/null 2>&1
}

bridge_has_port() {
    [ -n "$bridge_link" ] || return 1
    [ -e "/sys/class/net/${bridge_link}/brif/${host_veth}" ]
}

write_probe_commands() {
    printf '%s\n' 'echo VETH_PROBE_BEGIN'
    printf '%s\n' 'printf "hostname="; hostname'
    printf '%s\n' 'printf "kernel="; uname -r'
    printf '%s\n' 'printf "net_devices="; sed -n "3,$s/:.*//p" /proc/net/dev 2>/dev/null | tr "\n" ","; echo'
    printf '%s\n' 'printf "ip_link_count="; ip -o link show 2>/dev/null | wc -l'
    printf '%s\n' 'printf "routes="; cat /proc/net/route 2>/dev/null | wc -l'
    printf '%s\n' 'printf "ipv6_if="; cat /proc/net/if_inet6 2>/dev/null | wc -l'
    printf '%s\n' 'echo VETH_PROBE_END'
    printf '%s\n' 'exit'
}

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    printf 'Container is already running, refusing to take over: %s\n' "$name" >&2
    exit 1
fi
if host_link_exists; then
    printf 'Host veth already exists, refusing to reuse it: %s\n' "$host_veth" >&2
    exit 1
fi
if [ "$bridge_mode" -eq 1 ] && ! bridge_link_exists; then
    printf 'Configured bridge does not exist, refusing to start container: %s\n' "$bridge_link" >&2
    printf 'Create the isolated lab bridge first or remove lxc.net.0.link from: %s\n' "$config_file" >&2
    exit 1
fi

printf '%s\n' '# LXC veth network probe'
printf '\n'
printf 'container=%s\n' "$name"
printf 'state_dir=%s\n' "$state_dir"
printf 'config=%s\n' "$config_file"
printf 'host_veth=%s\n' "$host_veth"
[ "$bridge_mode" -eq 0 ] || printf 'bridge=%s\n' "$bridge_link"
printf 'log=%s\n' "$log_file"
printf '\n'

{
    printf '%s\n' '# LXC veth network probe'
    printf 'generated_utc=%s\n' "$stamp"
    printf 'container=%s\n' "$name"
    printf 'state_dir=%s\n' "$state_dir"
    printf 'config=%s\n' "$config_file"
    printf 'host_veth=%s\n' "$host_veth"
    [ "$bridge_mode" -eq 0 ] || printf 'bridge=%s\n' "$bridge_link"
    printf '\n## config network lines\n'
    grep -E '^lxc\.net\.|^lxc\.start\.auto' "$config_file" || true
    printf '\n## host interfaces before\n'
    ip -o link show || true
    if [ "$bridge_mode" -eq 1 ]; then
        printf '\n## bridge before\n'
        brctl show "$bridge_link" 2>&1 || true
    fi
    printf '\n## detached lifecycle probe\n'
} >"$log_file"

if ! lxc-start -d -P "$state_dir" -n "$name" -- /bin/sh -c 'trap "exit 0" TERM INT; while :; do sleep 60; done' >>"$log_file" 2>&1; then
    fail_with_log "Detached veth start failed; inspect log: $log_file"
fi
started=1

i=0
while [ "$i" -lt 10 ]; do
    if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

lxc-info -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
printf '\n## host veth while running\n' >>"$log_file"
if host_link_exists; then
    ip -o link show "$host_veth" >>"$log_file" 2>&1 || true
    host_veth_running=OK
else
    printf 'missing: %s\n' "$host_veth" >>"$log_file"
    host_veth_running=WARN
fi
bridge_port_running=SKIPPED
if [ "$bridge_mode" -eq 1 ]; then
    printf '\n## bridge while running\n' >>"$log_file"
    brctl show "$bridge_link" >>"$log_file" 2>&1 || true
    if bridge_has_port; then
        bridge_port_running=OK
    else
        bridge_port_running=WARN
    fi
fi

lxc-stop -P "$state_dir" -n "$name" >>"$log_file" 2>&1 || true
started=0

if lxc-info -s -P "$state_dir" -n "$name" 2>/dev/null | grep -q 'RUNNING'; then
    fail_with_log "Container still RUNNING after detached veth stop; inspect log: $log_file"
fi

printf '\n## host veth after stop\n' >>"$log_file"
if host_link_exists; then
    ip -o link show "$host_veth" >>"$log_file" 2>&1 || true
    host_veth_cleanup=WARN
else
    printf 'absent: %s\n' "$host_veth" >>"$log_file"
    host_veth_cleanup=OK
fi
bridge_port_cleanup=SKIPPED
if [ "$bridge_mode" -eq 1 ]; then
    printf '\n## bridge after detached stop\n' >>"$log_file"
    brctl show "$bridge_link" >>"$log_file" 2>&1 || true
    if bridge_has_port; then
        bridge_port_cleanup=WARN
    else
        bridge_port_cleanup=OK
    fi
fi

printf '%s\n' 'Collecting foreground veth evidence...'
printf '\n## foreground evidence\n' >>"$log_file"
if ! write_probe_commands | lxc-start -F -P "$state_dir" -n "$name" >>"$log_file" 2>&1; then
    fail_with_log "Foreground veth probe failed; inspect log: $log_file"
fi

if ! grep -q 'VETH_PROBE_BEGIN' "$log_file" || ! grep -q 'VETH_PROBE_END' "$log_file"; then
    fail_with_log "Veth probe markers missing; inspect log: $log_file"
fi

printf '\n## host interfaces after foreground\n' >>"$log_file"
ip -o link show >>"$log_file" 2>&1 || true
if host_link_exists; then
    host_veth_final=WARN
else
    host_veth_final=OK
fi
bridge_port_final=SKIPPED
if [ "$bridge_mode" -eq 1 ]; then
    printf '\n## bridge after foreground\n' >>"$log_file"
    brctl show "$bridge_link" >>"$log_file" 2>&1 || true
    if bridge_has_port; then
        bridge_port_final=WARN
    else
        bridge_port_final=OK
    fi
fi

if [ "$bridge_mode" -eq 1 ]; then
    printf '%s\n' '# LXC isolated bridge network probe summary'
else
    printf '%s\n' '# LXC veth network probe summary'
fi
printf '\n'
printf 'container=%s\n' "$name"
printf 'host_veth=%s\n' "$host_veth"
[ "$bridge_mode" -eq 0 ] || printf 'bridge=%s\n' "$bridge_link"
printf 'log=%s\n' "$log_file"
printf '\n'
case "$host_veth_running" in
    OK) printf 'OK: host veth appeared while detached container was running\n' ;;
    WARN) printf 'WARN: host veth was not observed while detached container was running\n' ;;
esac
case "$host_veth_cleanup" in
    OK) printf 'OK: host veth disappeared after detached stop\n' ;;
    WARN) printf 'WARN: host veth still existed after detached stop\n' ;;
esac
case "$host_veth_final" in
    OK) printf 'OK: host veth absent after foreground probe\n' ;;
    WARN) printf 'WARN: host veth still exists after foreground probe\n' ;;
esac
if [ "$bridge_mode" -eq 1 ]; then
    case "$bridge_port_running" in
        OK) printf 'OK: host veth appeared as bridge port while detached container was running\n' ;;
        WARN) printf 'WARN: host veth was not observed as bridge port while detached container was running\n' ;;
    esac
    case "$bridge_port_cleanup" in
        OK) printf 'OK: bridge port disappeared after detached stop\n' ;;
        WARN) printf 'WARN: bridge port still existed after detached stop\n' ;;
    esac
    case "$bridge_port_final" in
        OK) printf 'OK: bridge port absent after foreground probe\n' ;;
        WARN) printf 'WARN: bridge port still exists after foreground probe\n' ;;
    esac
fi
grep -E 'VETH_PROBE_|^hostname=|^kernel=|^net_devices=|^ip_link_count=|^routes=|^ipv6_if=' "$log_file"
if [ "$bridge_mode" -eq 1 ]; then
    printf '\nResult: ISOLATED BRIDGE PROBE COMPLETE. No production interface was attached.\n'
else
    printf '\nResult: VETH PROBE COMPLETE. No bridge was configured.\n'
fi

if [ "$host_veth_cleanup" = WARN ] || [ "$host_veth_final" = WARN ] ||
    [ "$bridge_port_cleanup" = WARN ] || [ "$bridge_port_final" = WARN ]; then
    printf '\nManual cleanup may be required for host veth: %s\n' "$host_veth" >&2
    [ "$bridge_mode" -eq 0 ] || printf 'Manual bridge inspection may be required: %s\n' "$bridge_link" >&2
    exit 1
fi
