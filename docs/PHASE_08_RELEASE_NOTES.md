# SeiCycle 1.0.1+2 — release candidate

Resumed verification: 24 October 2026 (Asia/Jakarta). Historical observations below retain their dates; final results are in the test and handoff reports.

17 October 2026, Asia/Jakarta. **Owner review required; production acceptance is incomplete.** Release identity/version still requires owner comparison with any external distribution history.

## Changed

- Fixed Education editor opening for article, video and SOP; its previous intrinsic-layout exception prevented create/edit.
- Education saves retain inputs/errors until success, prevent duplicate taps and use stable creation retries. Edits preserve existing category/tags/thumbnail, SOP tools/safety and video duration; busy forms cannot be accidentally dismissed. Keyboard/large-text layouts corrected.
- Productivity bars use actual observation dates, readable widths and horizontal scrolling for dense data. Line gaps remain empty and tooltips preserve quantity/unit. No fabricated calendar measurements or zero-fill added.
- Revoked cached screens, details/dialogs and notification subscriptions when session role/access changes; harmless profile updates preserve drafts. Missing-profile state no longer throws while revoking access.
- Corrected Inventory-only report presence, report dropdown overflow and default complete 30-day calendar window.
- Hardened last-effective-Admin protection for legacy inactive/deleted/reversed profile flags.
- Enlarged the unchanged Kebun Sei mark inside the app and in the Android launcher/APK icon, with safe adaptive masking and branded launch resources. Added a dedicated monochrome notification icon.
- Added explicit Internet permission to release manifest; retained application identity and original design. Replaced deprecated Kotlin JVM-target setter with supported compiler options.
- Replaced debug release-signing fallback with owner-managed signing and credential/certificate guards; incremented candidate version from 1.0.0+1.
- Rewrote README around current functionality, Android scope, authentication, trusted worker and real release/deployment status. Added full Phase 08 audit/test/security/deployment/release/UAT/handoff records.

## Features retained from Phases 01–07

Original green/cream shell and four destinations, five-module Logbook, batch lifecycle, inventory/ledger, schedules/reminders, Dashboard monitoring, finance/sales/circular flow, PDF/Excel, Education detail, recipient inbox/recommendations and 17-category Admin workflows remain in source. The [audit matrix](PHASE_08_FINAL_AUDIT.md) maps features to tests, roles and runtime limits.

## Compatibility and rollout

No dependency upgrade, Firestore schema migration, production data cleanup or Rules relaxation was performed. Current deployed Rules match source; 96 indexes are READY. Operational Education CRUD uses atomic direct Firestore audit; generic Admin privileged workflows require the trusted worker. Legacy unsupported writes need an updated client rather than permissive Rules.

The owner authorized a new release key outside Git. Existing debug-signed installations cannot update directly to the new certificate: uninstall requires explicit approval and removes local app data. It does not delete Firestore cloud records. Keep the same production signing key for future updates and complete portable backup before distribution.

## Known release gates

- Verify trusted worker host, managed credentials/IAM, restart/monitoring and identity-job recovery.
- Complete dedicated-account role UAT, approved signed installation and native notification/export acceptance.
- Verify owner key backup/recovery, external version-code history and publication decision.
- Respect bounded datasets, missing historical masters, uncertain source evidence and dependency maintenance caveats. Do not reconstruct physical stock or allow arbitrary deletion.

Actual counts, APK checksum and device findings are in [test report](PHASE_08_TEST_REPORT.md). This note does not declare the application production-ready or claim a production worker deployment.

24 October qualification: the signed candidate installed and the owner logged in; main navigation and Education open/cancel smoke completed. Live Recommendations is blocked by invalid/unavailable historical references. Native exports, generic Admin/worker, full-role/reminder UAT and portable key backup remain unresolved release gates.
