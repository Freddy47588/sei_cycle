# Phase 08 UAT checklist

Resumed verification: 24 October 2026 (Asia/Jakarta). Historical observations below retain their dates; final results are in the test and handoff reports.

Prepared 17 October 2026 (Asia/Jakarta). **This document is a test protocol, not a record of completed manual acceptance. Every unchecked item and every PENDING cell remains unverified.** Executed automation is recorded separately in [test report](PHASE_08_TEST_REPORT.md); release classification is in [Android release report](PHASE_08_ANDROID_RELEASE.md).

Use a demo Emulator project or owner-approved isolated staging data for creation, corrections, reversals, deletion and identity tests. Production destructive testing is prohibited. Do not recreate retired sample Inventory, guess physical balances from historical ledgers, or publish real records/screenshots/account identifiers. Production-changing rollout requires owner approval. A missing device, key, worker, test identity or approved environment is **BLOCKED**, never PASS.

## Execution record

Before changing a result below, record the candidate revision/build and package/version, sanitized environment, test role alias, device model/Android version, logical viewport and text scale, time (Asia/Jakarta), scenario IDs, expected/actual result, and a repository-relative pointer to private ignored evidence. Avoid emails, UIDs, credentials, local workstation paths, production exports and private financial details in public records. Retest failed scenarios after a fix against the updated candidate.

| Evidence | Actual result |
| --- | --- |
| Candidate revision / build / package / version | PENDING — record actual tested candidate |
| Emulator/staging project and approved isolated test fixtures | PENDING — use sanitized aliases, not credentials |
| Physical Infinix X6833B / Android version | Android device detected; initial app read performed. Android 14 and initial debug 1.0.1+2 installation/navigation/create-form cancellation verified on 17 October; final branding/signed acceptance is recorded in the test report |
| Device installation, startup and crash/logcat review | Final signed installation passed after explicit uninstall approval; login screen visible, non-debuggable, no VM-service banner or fatal/uncaught startup patterns. Full role/native acceptance remains pending |
| Owner signing-key preparation approval | Approved; RSA-4096 key generated outside repository with DPAPI-protected credentials. Signed APK/certificate verification passed on 24 October; approved installation and login-screen startup passed. User subsequently confirmed login on the device |
| Owner/user production acceptance and signed-release decision | PENDING |

Automated preparation is separate from this manual record: 28 chart, eight role-boundary, two final report, five notification-service and 13 Education UI cases passed. The Education service focused run passed eight new plus 20 existing regression cases; demo Rules passed 175 and Admin worker passed 36. These scopes overlap broader regressions and must not be summed into a claimed final Flutter total. On 24 October clean analyzer and the final 503-case Flutter suite passed; 175 Rules and 36 Admin cases passed again. Final APK/device evidence is in the test report. Every role/viewport/manual scenario below remains PENDING.

The Education blocker was reproduced and fixed locally: a `LayoutBuilder` inside `AlertDialog` prevented create/edit through intrinsic sizing. The editor now uses bounded vertical controls, preserves drafts after errors, blocks duplicate/back actions while saving, reuses stable retry IDs, retains metadata and handles keyboard scrolling. Its passing UI/service/Rules cases prepare EDU-01/02 acceptance; they do not check those manual boxes.

## Role acceptance

Run every applicable scenario with independent staged identities. UI hiding alone is insufficient for authorization; direct unauthorized SDK attempts belong to demo-only Rules tests.

| Role/account condition | Required behavior | Actual manual result |
| --- | --- | --- |
| Active Admin | Operational management, Finance/Sales, content management and reviewed worker requests; protected backup/audit controls remain restricted | PENDING |
| Active `operator_lapangan` | Batch/Logbook/Inventory/Schedule/Circular Flow management; operational reads; no Finance/Sales/Admin management | PENDING |
| Active legacy `operator` | Same operational capabilities as field operator | PENDING |
| Active `operator_keuangan` | Finance management, Sales read, operational/report reads; no Sales creation or operational/Admin management | PENDING |
| Active legacy `mitra` | Allowed operational/Education reads; no management or Finance | PENDING |
| Active legacy `peserta_edukasi` | Allowed operational/Education reads; no management or Finance | PENDING |
| Inactive profile; disabled Auth identity; absent/tombstoned profile | No authorized business writes; clear explanatory login/profile state; sign-out available where applicable | PENDING |
| Signed out | Login/registration/reset only; protected direct reads/writes denied | PENDING |
| Same UID role promotion/downgrade while signed in | Menus/subscriptions/cached reports/recommendations/export permission refresh; previous-role Finance data and draft actions unavailable | PENDING |
| Switch account / logout and immediate new login | No old drafts, badges, receipt state, role-dependent content or previous-account reminders | PENDING |

## Required viewport and accessibility sweep

Widths are logical pixels, not screenshot bitmap pixels. For each cell run normal text (`1.0`), enlarged text (`1.4`) and an accessibility stress pass at `2.0` or the device's maximum supported large-font setting. Also increase Android display size, use TalkBack where available, open keyboard/date pickers/dialogs, and test portrait/landscape. A widget no-overflow assertion covers its selected fixture; it does not complete these manual cells.

| Screen group | 320 px | 360 px | 393 px | 768 px | 1280 px |
| --- | --- | --- | --- | --- | --- |
| Login, register, reset, inactive profile | PENDING | PENDING | PENDING | PENDING | PENDING |
| Four primary tabs, Lainnya sheet, sidebar, Profile | PENDING | PENDING | PENDING | PENDING | PENDING |
| Dashboard KPI cards, five modules, filters and chart | PENDING | PENDING | PENDING | PENDING | PENDING |
| All five Logbook forms, list/detail and notes editor | PENDING | PENDING | PENDING | PENDING | PENDING |
| Batch list/form/detail, picker, activities | PENDING | PENDING | PENDING | PENDING | PENDING |
| Inventory master/movement/correction/history | PENDING | PENDING | PENDING | PENDING | PENDING |
| Schedule/calendar/checklist/reminder controls | PENDING | PENDING | PENDING | PENDING | PENDING |
| Finance form/list/detail, Sales, Circular Flow | PENDING | PENDING | PENDING | PENDING | PENDING |
| Report filters/results/export and external viewers | PENDING | PENDING | PENDING | PENDING | PENDING |
| Education catalog/article/SOP/video/editor | PENDING | PENDING | PENDING | PENDING | PENDING |
| Notification inbox/reference and recommendations | PENDING | PENDING | PENDING | PENDING | PENDING |
| Admin categories/record forms/preview/result/history | PENDING | PENDING | PENDING | PENDING | PENDING |

For every applicable screen verify: no clipped headings/values/units; wrapped or intentionally scrollable dense content; visible validation messages; 48 px controls where applicable; meaningful screen-reader labels/focus order; reachable save/cancel above keyboard; scrollable sheets/dialogs; visible snackbars; sensible Indonesian dates/currency; loading eventually settles; successful save opens the correct record; Android back does not lose work without expected behavior; empty and error states cannot present example data as actual.

## Scenario acceptance

### Account, shell and branding

- [ ] AUTH-01: correct email/password login, incorrect password/email, disabled account and network interruption show accurate states; repeat taps do not create duplicate requests.
- [ ] AUTH-02: registration creates one own profile without privileged role; duplicate email/profile retry and failed connection recover without a misleading success.
- [ ] AUTH-03: reset request uses trimmed account email, does not disclose account existence and opens a working approved reset workflow.
- [ ] AUTH-04: cold start/session persistence, background/resume, logout and rapid account switch preserve the correct identity and clear prior-session content.
- [ ] AUTH-05: no Google sign-in entry point or obsolete reconciliation menu; current logo, launcher, splash, display name and notification icon render correctly.
- [ ] NAV-01: Dashboard/Logbook/Edukasi/Notifikasi remain the four primary destinations; Lainnya and desktop/tablet sidebar expose only allowed destinations.
- [ ] NAV-02: change a staged user's role while Dashboard, inbox, report/export, recommendations, Admin panel and an unsaved operational form are open; old permission content/actions clear and current-role subscriptions load.

### Logbook and Batch

- [ ] LOG-01: complete each Ayam Kampung, Maggot BSF, Cacing Tanah, Lele and Tanaman form using actual staged observations; verify saved values, actor, timestamp, units and detail route.
- [ ] LOG-02: reject empty required fields, negative/invalid numbers, mismatched units, impossible dates/references and unobserved defaults; input remains editable after validation failure.
- [ ] LOG-03: double tap, retry after failed save and ambiguous reconnect create one Logbook and one set of inventory/production effects using the original request ID.
- [ ] LOG-04: inspect list/detail, all module/date/custom filters, loaded-window search and multiple pages; cancellation restores active filter and late old responses cannot replace current data.
- [ ] LOG-05: notes editing changes notes only, records protected history and rejects stale edits; stock/production remain unchanged.
- [ ] LOG-06: verify active matching Batch and explicit no-Batch modes, legacy aliases, persistence after restart and read-only completed/archived Batch semantics.
- [ ] BATCH-01: create all module types with unique normalized codes; duplicate code, wrong module, invalid unit/quantity/date and stale edit fail clearly.
- [ ] BATCH-02: planned → active → completed → archived transitions, metadata, history, active picker and related records remain correct; invalid reverse transitions fail.
- [ ] BATCH-03: complete a Batch concurrently with a Logbook save; transaction rechecks state and leaves no partial inventory/production effects.
- [ ] BATCH-04: Admin dependency preview identifies actual dependents; cancel leaves data untouched; blocked deletion explains required resolution.

### Inventory, schedules and notifications

- [ ] INV-01: create/edit a master, optional opening balance and correct units/classification; empty database has no invented/recreated master.
- [ ] INV-02: stock in/out and measured absolute correction store correct before/after/delta/reason; reject insufficient stock, invalid values, stale/concurrent unsafe writes and duplicate replay.
- [ ] INV-03: current/low/out-of-stock display and complete history agree; linked Batch/Logbook/Sale references open exact records; missing historical masters are explained without restoring stock.
- [ ] SCH-01: create/edit schedule, date/module/Batch filter and calendar; explicitly mark pending/done/skipped with required reason and correct actor/time.
- [ ] SCH-02: stale checklist/edit fails safely; schedule-to-Logbook preserves module/Batch context; deleted/done/skipped schedules stop reminding.
- [ ] NTF-01: UID-targeted notification is visible only to its recipient; role/all broadcast is visible only to eligible users; mark-one/all updates own receipts without altering another recipient.
- [ ] NTF-02: category/unread filters, refresh/retry, badge and related-record navigation agree; missing/deleted/unauthorized Finance reference is explained safely.
- [ ] NTF-03: unchanged repeated alert creation does not reset read state; changed/regenerated alert becomes unread appropriately; oversized sources fail explicitly instead of partial mark-all success.
- [ ] REM-01: Android permission granted/denied paths, schedule/update/replacement/cancellation, logout/account switch and background/resume sync work without duplicate reminders.
- [ ] REM-02: device reboot, OEM battery optimization and timezone change preserve intended instants or record the exact observed restriction. Maximum 50 schedules within 14 days is communicated accurately.

### Dashboard, Finance, Sales, Circular Flow and reports

- [ ] DASH-01: KPI totals and five-module units match independently verified staged inputs; actual zero differs from missing data and failed/incomplete query.
- [ ] DASH-02: period/Batch/module filters, timeline ordering and stale response handling remain correct; missing historical parents isolate errors without hiding independent valid metrics.
- [ ] CHART-01: 7/30/90/custom range, single-day, sparse/dense observations, all-zero/empty and multiple series show actual date/unit/tooltips without overlapping labels or unreadable bars.
- [ ] CHART-02: absent measurements stay absent, actual zero stays visible, no interpolated/fake zero observations, and long dates remain legible at 320/360/393 px with enlarged text.
- [ ] FIN-01: manual income/expense, category/date filters, detail/edit audit and correction/deletion update totals; net cash flow is labeled separately from accounting profit.
- [ ] SALE-01: approved staged Admin sale writes one receipt, exact stock deduction and paid-income linkage atomically; invalid payment/quantity/unit/stock or failed commit leaves no partial documents.
- [ ] SALE-02: trusted Admin cancellation reverses verified stock and excludes original paid income; repeated cancellation cannot double-reverse; intervening activity/missing evidence blocks unsafe permanent cleanup.
- [ ] FLOW-01: actual flow preserves material/module/unit/date and optional source references; linking existing ledger does not move stock twice; illustrative flows never become actual measurements.
- [ ] RPT-01: operational/current Inventory/Finance reports use correct date/module/source distinctions; unauthorized roles never query, display or export financial data, including after a live role downgrade.
- [ ] RPT-02: PDF and Excel open in actual Android viewers, multi-page/long text/decimal quantities/units/Rupiah totals are readable and match verified staged inputs; native share/save/cancel/failure paths work.

### Education and recommendations

- [ ] EDU-01: published article/SOP/video list and detail, module/type/loaded-window search, pagination and retry work without draft/archived disclosure to non-Admin.
- [ ] EDU-02: Admin create/edit/publication/archive/soft-delete preserves atomic audit; stale concurrent editor is rejected; empty SOP/unsafe URL rejected; HTTPS video opens safely in native browser. Open the bounded create/edit dialog with keyboard and enlarged text, interrupt a save, retry without losing draft/metadata or duplicating content/audit, and cancel/confirm deletion explicitly.
- [ ] REC-01: each of five modules receives only justified rule-based advice from actual sources; missing data/current Inventory gives explicit uncertainty rather than invented stability or estimated actual harvest.
- [ ] REC-02: actual production comparisons preserve product/unit; Finance recommendations appear only for F roles and disappear immediately on permission change; deleted/seed/reversed sources cannot produce operational totals.

### Trusted Admin and recovery — isolated staging/Emulator only

- [ ] ADM-01: separately exercise all 17 categories from the [final audit](PHASE_08_FINAL_AUDIT.md); record supported create/read/update/archive/delete/reversal outcomes and expected collection-specific restrictions.
- [ ] ADM-02: exact target path, actor, operation, reason, before/after and all dependents are visible in preview; cancel does nothing; only explicit confirm permits execution.
- [ ] ADM-03: non-Admin/inactive/disabled identity, direct forged SDK write, wrong actor/path, expired/stale preview and replay reject on trusted side without mutation or financial leak.
- [ ] ADM-04: introduce a dependency after preview; execution requires fresh review. Over-500 root or unsupported schema must block rather than execute a partial graph.
- [ ] ADM-05: worker unavailable/timeout leaves a visible request ID/status; recheck existing request before retry. No false completion or duplicate execution.
- [ ] ADM-06: audited mutation, immutable recovery backup, protected result and preserved child audit history match the exact staged change; app clients cannot edit/delete protected evidence.
- [ ] ADM-07: provisioning/deactivation/profile-only versus Auth deletion, UID collision, removed-profile tombstone and last active Admin protections behave correctly.
- [ ] ADM-08: controlled crash between Auth operation and Firestore acknowledgment produces a recoverable processing/needs-review job; exact UID inspection/recovery and staged restore rehearsal complete without blind identity replay.

## Release installation and acceptance decision

- [ ] REL-01: final APK package, unique approved version code/name, SHA-256 and signing certificate match the release report; certificate is the owner-approved production key, not debug.
- [ ] REL-02: install on the target device and verify cold launch without Flutter debug service, approved non-destructive Firebase login/read, background/reopen, navigation, notifications and export.
- [ ] REL-03: if an incompatible existing signature prevents installation, do not uninstall automatically; record owner permission before uninstall because local app data is removed.
- [ ] REL-04: fatal/crash/exception review completed against private ignored runtime evidence; screenshots show actual sanitized verified screens only.
- [ ] REL-05: approved trusted worker host/IAM/monitoring, exact deployed Rules and READY indexes are independently verified; no source-file-only deployment claims.
- [ ] REL-06: every failed critical scenario is fixed and retested; all required role/viewport/device gates have evidence; owner acceptance and rollback/recovery ownership are recorded.

**Current manual acceptance: PENDING.** A local debug APK, passing mocked tests, successful byte export, source Rules or a draft PR cannot complete the unchecked device, production or signing gates.

## Executed signed-session smoke ? 24 October

Owner-approved signed install/startup and privately entered login passed. Main navigation and Education create/edit opening/cancellation were inspected. Inventory/Schedule/Finance/Sales/Flow/Reports menu reads were sampled. The launcher icon was visually verified. No scripted business save/delete/share/print was submitted. Recommendations showed a historical-reference integrity error and remains BLOCKED for acceptance. Native exports, generic Admin/worker execution, remaining roles and reminder/OEM scenarios remain unchecked.
