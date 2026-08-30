# lxc-on-dsm hook snippets

Place reviewed `*.sh` snippets here when building a lab package variant.

Installed snippets run inside the container through:

```text
/etc/lxc-on-dsm/start.d/*.sh
```

The package does not install any service snippets by default.

Included examples:

- `marker.example.sh` writes a validation marker into `/tmp`.
- `httpd.example.sh` starts a tiny lab HTTP-like service when `httpd`,
  BusyBox `httpd`, or `nc` is available in the container image.
