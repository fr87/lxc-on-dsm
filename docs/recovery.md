# Update and recovery plan

Before installation is implemented, the project will provide a checksum manifest, configuration export, data backup instructions, post-update compatibility check, idempotent reinstall, and data-preserving uninstall.

After a DSM update, container autostart remains disabled until the compatibility gate passes. Rollback restores the prior package artifact and configuration without requiring a DSM system-volume restore.

## Post-update gate

After every DSM update:

1. Run `scripts/analyze-dsm.sh` into a fresh artifact directory.
2. Compare the new report against the last known-good hardware report.
3. Run `scripts/evaluate-report.sh` against the new report.
4. Keep all container autostart disabled until the preflight has no blocker.
5. Reinstall or repair only project-owned files under the package and container data locations.
6. Regenerate or verify the local lifecycle profile with
   `scripts/verify-macvlan-profile.sh` before starting any networked container.
7. Start only through `scripts/start-macvlan-profile.sh` and stop through
   `scripts/stop-macvlan-profile.sh` until DSM package lifecycle integration is
   implemented.
