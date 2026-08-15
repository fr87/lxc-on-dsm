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
8. Use `scripts/doctor-macvlan-profile.sh` for read-only status checks before
   any manual repair after an interrupted start/stop or DSM update.
9. Treat `spk/` as a template skeleton until package payload assembly and
   install/upgrade guards are implemented and tested.
10. Treat a built `.spk` as an artifact only until the Virtual DSM installation
    plan has been reviewed; do not install it directly after archive creation.

After a clean manual stop, the expected idle state is:

- container stopped
- no lifecycle runtime-state file
- no host shim interface
- no lifecycle route
- `scripts/doctor-macvlan-profile.sh` returns `MACVLAN DOCTOR PASS`
