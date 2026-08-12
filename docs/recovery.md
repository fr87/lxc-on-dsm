# Update and recovery plan

Before installation is implemented, the project will provide a checksum manifest, configuration export, data backup instructions, post-update compatibility check, idempotent reinstall, and data-preserving uninstall.

After a DSM update, container autostart remains disabled until the compatibility gate passes. Rollback restores the prior package artifact and configuration without requiring a DSM system-volume restore.
