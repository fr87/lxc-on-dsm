#!/bin/sh
# Example start.d snippet: start a tiny HTTP-like lab service when available.
# Intended for lab validation only.
set -eu

status=SKIPPED
reason=
docroot=/var/www/lxc-on-dsm
port=8080
evidence=/tmp/lxc-on-dsm-httpd-example.env

mkdir -p "$docroot"
cat >"${docroot}/index.html" <<'EOF'
<!doctype html>
<html>
<head><meta charset="utf-8"><title>lxc-on-dsm</title></head>
<body><h1>lxc-on-dsm example service</h1><p>Container start hook executed.</p></body>
</html>
EOF

if command -v httpd >/dev/null 2>&1; then
    if httpd -p "$port" -h "$docroot" >/tmp/lxc-on-dsm-httpd-example.log 2>&1; then
        status=STARTED
    else
        status=FAILED
        reason=$(tr '\n' '|' </tmp/lxc-on-dsm-httpd-example.log 2>/dev/null || true)
    fi
elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx 'httpd'; then
    if busybox httpd -p "$port" -h "$docroot" >/tmp/lxc-on-dsm-httpd-example.log 2>&1; then
        status=STARTED
    else
        status=FAILED
        reason=$(tr '\n' '|' </tmp/lxc-on-dsm-httpd-example.log 2>/dev/null || true)
    fi
elif command -v nc >/dev/null 2>&1; then
    (
        while :; do
            body='lxc-on-dsm example service'
            {
                printf 'HTTP/1.1 200 OK\r\n'
                printf 'Content-Type: text/plain\r\n'
                printf 'Content-Length: %s\r\n' "${#body}"
                printf '\r\n'
                printf '%s' "$body"
            } | nc -l -p "$port"
        done
    ) >/tmp/lxc-on-dsm-httpd-example.log 2>&1 &
    status=STARTED
    reason=netcat-fallback
else
    status=MISSING
    reason=httpd-or-nc-not-found
fi

{
    printf 'status=%s\n' "$status"
    printf 'port=%s\n' "$port"
    printf 'docroot=%s\n' "$docroot"
    printf 'reason=%s\n' "$reason"
} >"$evidence"
