# Phase 08 — QA evidence

Resumed verification: 24 October 2026 (Asia/Jakarta). Historical observations below retain their dates; final results are in the test and handoff reports.

17 October 2026, Asia/Jakarta. Baseline `f3380c3`; final reviewed revision is recorded in [handoff](PHASE_08_FINAL_HANDOFF.md). Raw logs, screenshots, APKs, credential checks and production audit responses remain ignored/private. No destructive fixture used production.

## Toolchain and independent final gates

| Check | Actual result |
| --- | --- |
| Flutter / Dart | 3.44.2 stable / 3.12.2 |
| Node | 24.5.0; satisfies worker Node ≥22 |
| Java / Android | Android Studio JDK 21; Java 17 bytecode target, Android SDK 36.1 available |
| Doctor | Android licenses category warning; network/toolchain/device detected. Licenses were not blindly accepted |
| Pre-edit pub get / outdated / analyzer | Completed; analyzer no issues |
| Official dependency metadata | 102 hosted versions plus direct upstream checks completed, zero flags; dependencies unchanged |
| Final clean / pub get / outdated | Completed successfully; 39 upgradable locked and 13 constrained below resolvable in the 24 October rerun; no lockfile change |
| Final analyzer / full Flutter suite / debug build | **No issues; 503 Flutter tests passed on 24 October, zero failures**. Earlier 437/495-case runs passed before the final eight branding cases; final Android debug build passed (212.9s), signed release build passed (249.3s) |
| Full Firestore Rules suite | **175 passed again on 24 October**, zero failed/skipped; 155 existing + 15 Phase 07/security + 5 Education lifecycle cases |
| Admin worker suite | **36 passed again on 24 October**, zero failed/skipped; includes Firestore/Auth emulators |
| Offline Node audit regressions | **15 passed**, zero failed/skipped |
| Python audit regressions | **11 passed** |
| Worker npm advisory audit | Zero known vulnerabilities at check time; deprecated transitives remain documented |
| Signing guards | Missing credential configuration rejected; actual Android debug certificate rejected; authorized owner release key validation passed |
| Release APK / checksum / metadata | **Built and verified on 24 October**, 70,783,903 bytes (67.5 MiB), owner release certificate, non-debuggable, correct package/version/Internet permission. SHA-256 `b7f879d536c808e882370c68398a1c21d07bdd2fe906c97e3c2da02b59fc57e5` |
| Merge/whitespace | `origin/main` is an ancestor; read-only merge review found no conflict; final staged checks required before push |

Final QA was started after `flutter clean`, followed by resolver, outdated, analyzer, all Flutter tests and debug build (394.6 seconds from the clean); release uses the same reviewed source and authorized credentials. An intermediate analyzer found one missing brace in new Education code; it was fixed and the final analyzer passed. Earlier targeted failures below were retained as defect evidence and corrected; none were silently disabled.

## Phase 08 targeted regressions

| Area | Executed evidence |
| --- | --- |
| Productivity chart | **28 passed**: 1/7/30/90/366 days, 320/360/393/768/1280 px at 2x text, sparse observations, chronological dates, exact unit tooltips, fixed readable rods, scrollable dense data, genuine zero vs invalid/missing, line gaps without interpolation |
| Authorization/session | **8 passed**: same-UID role change invalidates notifications/badges/cached pages, preserves harmless-profile draft updates, revokes open details/dialogs on downgrade/logout/inactive/missing/error profile |
| Reports | **2 passed**: valid healthy Inventory-only report is not falsely empty; true empty report; 393 px at 1.4x text; complete 30-day local-calendar default |
| Notifications | **5 passed**: duplicate no-op, changed generation unread state, UID isolation, broadcast receipts/regeneration, 60-item mixed mark-all, >500 guard without partial writes |
| Education service | **8 new passed**, together with 20 existing Phase 07 tests (**28 targeted passed**): stable create retry after lost response, conflicting request reuse, all content types, metadata/tags and audit |
| Education UI | **22 passed in the final suite** (13 in the initial targeted run): create article/video/SOP at all five requested widths and 1.4x text; retained failed draft; stable retry/one content/audit; busy/cancel/back; keyboard and HTTPS validation; edits of title/module/status preserving metadata; cancelled/confirmed soft-delete; reader-only visibility |
| Education real Rules | **5 passed**, included in the 175 total: actual SDK transactions for article/video/SOP create/edit/publish/archive/soft-delete with before/after audit; sample provenance preserved; unauthorized field operator denied atomically |
| Branding | **8 passed**: decoded original logo, semantic image label, nonoverlapping Dashboard heading, reachable login action and usable navigation at 320/393/768/1280 px, scales 1.0/1.4; fixture screenshots rendered with actual logo |
| Last Admin | New pure/action matrix plus emulator regression within 36 Admin tests; legacy-disabled replacement cannot bypass last-effective-Admin guard |

Historical 373/169/34 counts from Phase 07 are not used as current pass evidence. Widget/service mocks validate local logic; they are not production UAT. Five-width regression now also covers navigation, primary pages, Logbook list/detail, Batch list/detail/form, Inventory/history/forms, Schedule, Dashboard charts, Finance/Sales/Circular Flow, profile and Education. These fixture tests do not complete the entire manual role/size matrix. Optional screenshot-font setup in touched tests now uses FLUTTER_ROOT rather than a workstation path. Existing export tests generate PDF and round-trip XLSX amounts/quantities and authorization; opening/sharing on physical Android remains a separate native gate.

## Defects found through failing tests

- Education create/edit initially threw `LayoutBuilder does not support returning intrinsic dimensions`: its responsive form row was inside AlertDialog intrinsic sizing. Removed that local layout dependency and bounded the form. The original catalog-only tests had never opened the editor.
- Education save closed the form before completion; failed writes discarded input and retries could create another ID. Save now stays in the dialog, disables duplicate submission/dismissal, retains errors/inputs and reuses a service-validated request ID. Video/SOP tags and hidden metadata survive edits.
- Education empty state overflowed behind the keyboard on a 320 px device; it now scrolls. Native acceptance still required.
- Report controls overflowed by 91 px at 393 px/1.4x text; the type dropdown now expands/ellipsizes. A healthy Inventory-only report and initial date boundary were corrected.
- Role-change tests exposed null profile `.requireData` crashing before revocation; explicit null handling now closes stale privileged routes and shows the missing-profile state.
- An initial role test cleanup waited indefinitely on fakeAsync stream closure; cleanup was corrected to the project's existing nonblocking teardown pattern. The final eight cases passed without suppressing application errors.

## Device and black-box evidence

Infinix X6833B detected via both Flutter and ADB; Android 14, physical 1080×2460 at density 480 (360 logical px). The initial installed `id.seicycle.app` was `1.0.0+1`, debuggable and signed with Android Debug. A read-only UI dump confirmed an authenticated Dashboard, expected branding, period controls and four main tabs plus Lainnya. This is an initial baseline observation, not final candidate acceptance.

On 17 October the new debug 1.0.1+2 APK installed with the same debug certificate, preserving local data. Dashboard, Logbook, Education and Notifications were opened; the Education create form opened and was canceled successfully. Private screenshot inspection confirmed the form layout. App-process logcat had zero fatal/uncaught patterns during that smoke interval. No production content was saved/deleted. Final branding build/device smoke results are recorded in the continuation below.

No logout/registration/password reset/live writes were performed without the dedicated test-account workflow. Full role acceptance, notification permission denial/grant, reminders/reboot/battery/timezone, native PDF/Excel opening/share, background/resume and signed installation must be recorded separately in [UAT](PHASE_08_UAT_CHECKLIST.md). Production business values and account identifiers are not published as screenshots.

## Reproduction

Follow the commands in [README](../README.md#pengujian), [release](PHASE_08_ANDROID_RELEASE.md) and [security](PHASE_08_SECURITY_AUDIT.md). Rules tests require the demo loopback Firestore emulator; Admin tests additionally require Auth emulator. Do not point fixture scripts at `seicycle-kebun-sei`.

## Continuation on 24 October

All 503 Flutter tests, eight focused branding tests, 175 Rules tests, 36 Admin tests, 15 Node audit tests and 11 Python tests passed. A test-only semantics handle leak in the new branding suite was corrected using try/finally; it no longer reports false failures. Java initially failed to create a local NIO pipe for Gradle/Firestore; a process-local writable temporary directory restored normal selector initialization. No firewall, global JDK, security setting or app dependency was changed.

Public screenshot `docs/images/phase08-login-320.png` is a verified fixture render of the current login screen with blank credentials. Private physical-device screenshots are not published.

## Acceptance

Safe local tests/signing are evidence toward a release candidate. Production worker host/IAM/recovery acceptance, real account/role UAT and owner publication approval remain **BLOCKED** where no evidence exists. A draft PR is appropriate; no production-ready label or automatic merge is authorized.

## Final artifact and debug-device smoke ? 24 October

Validated code commit: `924cdea403c3253eb34118ecbeb2cb9b3a919825`. Final signed candidate is `id.seicycle.app` 1.0.1 / code 2, verified APK Signature Scheme v2, with release certificate SHA-256 `f26fcac77490aaebd83afbb944c906a20f774358ff1fea81d96e11ef883a8e91`. APK metadata has no debuggable flag. AAPT confirms the adaptive launcher and dynamically named monochrome notification resource survive resource shrinking; obfuscated ZIP filenames are not used as a resource-existence test.

The final debug APK installed on Infinix without uninstall. The enlarged launcher logo was visually inspected in the actual app drawer and remained complete inside its mask. Dashboard, Logbook, Education and Notifications opened; the Education create form opened and was canceled. App-process logcat had zero fatal/uncaught patterns during that interval. The first immediate-start UI capture was still loading the profile; a later capture confirmed the screens after network initialization. No content save/delete was submitted. Normal app initialization may synchronize the current user profile metadata.

Owner explicitly approved uninstalling the debug installation and installing the exact signed APK hash above, accepting removal of local data/session. Signed installation/startup results are recorded below; authenticated role/native acceptance remains independent.

## Signed installation and startup ? 24 October

Owner-approved debug uninstall and signed installation both exited successfully. The signed login screen rendered on Infinix Android 14; installed version is 1.0.1/code 2 and package flags exclude DEBUGGABLE. During startup the app-process log had zero fatal/uncaught patterns and no Flutter VM-service banner. The owner then entered credentials privately and confirmed successful login on the device. The final authenticated read/navigation checks are recorded in the delivery follow-up. No user password was requested in chat or stored by this task.

## Authenticated signed-device results and remaining UAT

After owner-entered login, Dashboard, Logbook, Education and Notifications opened on the signed APK. Existing Education edit and create dialogs opened and were canceled without scripted save/delete. Inventory, Schedule, Finance, Sales, Circular Flow and Reports were navigated to; these are screen/read smoke observations, not approval of every record/total or CRUD action. The enlarged app-drawer icon was visually inspected, with the entire mark visible. The authenticated app-process log had zero fatal/uncaught patterns in the smoke interval.

**BLOCKED ? live Recommendations acceptance:** its integrity guard displayed that historical references were unavailable/invalid. Source inspection confirms this is the existing fail-closed relationship check; no guard was weakened and no missing master/balance was invented. The 22 historical missing-parent ledger records remain a separate observed data issue. A verified per-source data/backup review is required before claiming usable complete recommendations.

Native PDF/Excel export and generic Admin panel acceptance remain **unverified**: follow-up UI selection could not reliably reach those controls in the active device session. No share recipient, print job, privileged worker request or scripted business-data mutation was submitted. Offline PDF/XLSX generation/round-trip and role-security tests passed, but do not substitute for native acceptance. Full role matrix, reminder permission/denial/reboot/battery/timezone behavior and portable signing-key recovery remain pending.
