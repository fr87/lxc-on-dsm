#!/bin/sh
set -eu
[ "$#" -eq 2 ] || { printf 'Usage: %s HARDWARE_REPORT_DIR VDSM_REPORT_DIR\n' "$0" >&2; exit 2; }
for report in "$1" "$2"; do
    [ -f "$report/summary.env" ] && [ -f "$report/kernel-config.txt" ] || { printf 'Invalid report: %s\n' "$report" >&2; exit 2; }
done
printf '%s\n' '=== Summary differences ==='
diff -u "$1/summary.env" "$2/summary.env" || true
printf '%s\n' '=== Kernel feature differences ==='
diff -u "$1/kernel-config.txt" "$2/kernel-config.txt" || true
