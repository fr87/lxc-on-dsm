# Safety model

The analysis phase reads `/proc`, `/sys`, `/etc.defaults`, `/boot`, and `/usr/lib/modules`. It writes only to its requested output directory.

It does not install packages, alter DSM files, load modules, change sysctls, create namespaces or mounts, modify networking/firewalls, or start workloads.

Reports may contain hostnames, serial numbers, volume names, device details, or mount paths. Review and redact them before sharing. Never commit a raw physical-NAS report to a public repository.
