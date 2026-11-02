# Phase 07 — Education, inbox and operational recommendations

17 October 2026, Asia/Jakarta. Existing green/cream theme, logo, four main tabs and responsive sidebar are preserved. No sample seeding, Storage uploads, push-server deployment or stock-reconciliation feature was introduced.

## Education

Cards open a scrollable article/SOP/video detail page. SOP steps, tools and safety notes are displayed separately; content metadata and tags remain readable. External video links use the maintained official `url_launcher` package, `launchUrl` and external-browser mode. Only HTTPS URLs with a host and without embedded credentials are accepted; unsupported/unsafe legacy URLs get an explanatory state. Blank SOP steps are rejected after trimming. Models use actual document IDs for navigation.

The catalog retains title/preview search and module/type filters, adds Admin draft/published/archived filtering and reload, and starts with 20 records with incremental “Muat berikutnya”. Search applies to the loaded window; it is not a server-wide search engine. The cached stream is retained across search rebuilds. Error states provide retry. Candidate Rules enforce published-only reads for non-Admins instead of relying on hidden draft cards. Existing general content uses an empty module identifier; the five cultivation filters remain unchanged.

Admin publication/content forms remain available, and the Admin panel supplies reviewed permanent removal. Article/video/SOP saves, publication changes and soft deletion use atomic protected `education_edits` evidence. The editor forwards the version it opened, so concurrent changes are rejected rather than overwritten. Permanent removal uses the trusted worker.

## Notifications and local reminders

Inbox supports category and unread-only filters, chronological display, refresh/retry, mark-one/all, navigation badge and safe related-record inspection. Exact allowed document paths are reloaded from the server; missing/deleted references produce an explanatory screen, and finance references require finance capability.

UID-targeted messages no longer become visible to everyone sharing the target role. The broadcast query explicitly requires `userId == ''`. Shared broadcasts use `notification_receipts/{uid}/items/{id}` with server read timestamps; one recipient cannot mark a broadcast read for everyone. Broadcast regeneration with a newer timestamp becomes unread again for that user. Existing targeted messages preserve their `isRead` field. Mark-all processes every unread item in the verified bounded inbox and rejects oversized input instead of silently stopping after 50.

The combined listener is stable across local filters/rebuilds, and receipt changes update the badge. Existing deterministic low-stock/overdue IDs and transaction guards remain. Generic repeated notification creation no longer resets read state or timestamps when content/target/schedule are unchanged. Sample/deleted sources are excluded. Low-stock checks reload an actual master; historical ledger alone cannot generate an alert. Schedule-derived reminders require an actual pending source.

Existing local reminder behavior was inspected and retained: Android runtime permission, stable bounded IDs, update replacement, cancellation of no-longer-desired schedules, account/session cleanup, serialized synchronization, restart/resume sync and configured reboot receivers. `TZDateTime.from(scheduledAt, UTC)` preserves the recorded instant when scheduling; it does not reinterpret local wall time as UTC. Denied permissions return an explanatory message. Inexact device scheduling and OS delivery are not a server push service. Reboot, OEM battery restrictions, denied-permission behavior and timezone changes on Infinix remain real-device acceptance items; no device was attached during this phase.

Limits: inbox listeners reject more than 500 records per targeting branch; legacy inbox documents missing indexed required fields may need selected Admin review. Receipts currently trigger bounded inbox reloads and source checks; this favors correctness over high-volume efficiency. There is no new automatic trusted push backend and no promise of delivery when the app/worker is offline.

## Recommendations

The screen is labeled **Rekomendasi Operasional**. The engine uses validated current masters, actual Logbooks, pending schedules, active batches, production and genuine circular flows. It fetches Finance only for permitted roles. Source-query or integrity errors remain errors with retry; incomplete data does not become an empty successful total.

Removed the previous arbitrary productivity score, keyword-based mixed-unit totals and fixed species harvest ages. Each generated suggestion has a reason, action, priority (`high`, `medium`, `low`), relevant module/source and time context when known. Rules include:

- Low/out-of-stock master observations and a clear missing-inventory explanation.
- Overdue work and pending activities in the next seven days.
- Observation gaps of at least four days when a previous real Logbook exists.
- Active-batch follow-up and harvest preparation based on the batch's recorded expected date, explicitly labeled as a plan.
- Comparison of the last two actual production observations grouped by module/product/unit; the message explicitly avoids treating raw volume as normalized productivity.
- Current-month income/expense imbalance for finance roles, based on complete validated Finance sources.
- Review of genuine recorded circular use, without creating nutrient or stock movements.

Seed/deleted/reversed operational sources, invalid references, simulated harvest quantities and orphan ledger-derived stock are excluded. With insufficient evidence the engine displays **“Data belum cukup untuk menghasilkan rekomendasi yang akurat.”** It never declares operations stable merely because source data is absent. Persisted snapshots are managed separately through the Admin panel; Finance snapshots receive server-side role isolation.

## Dependency and verification scope

Removed `google_sign_in 7.2.0` and its provider-only transitives. Added `url_launcher 6.3.3` with its required native/web implementations; existing unrelated locked versions were retained. The trusted worker locks official `firebase-admin 14.5.0`, requiring Node 22+. No Android/Firebase SDK major migration was made.

`flutter pub outdated` reports 38 upgradable locked dependencies and 13 constrained below resolvable; newer versions alone are not deprecation. Official package/upstream metadata was inspected through `tools/dependency_health_audit.py`; any remaining fetch errors are reported in the completion report. Existing `excel` maintenance and archive/image constraints remain. npm installation reports transitive `glob 10.5.0` and `node-domexception 1.0.0` deprecation warnings under the official Admin SDK dependency tree; no untested override was applied. `npm audit --omit=dev` reported zero advisory findings at check time, which does not establish absence of all vulnerabilities or deprecations. Review these transitives before production worker rollout.

Analyzer, Flutter/Rules/Admin tests and debug APK evidence are summarized in the completion report. The only analyzer exclusion added is generated `node_modules`; no application diagnostics or deprecation lints were suppressed. Generated Kotlin cache is ignored. README and release configuration remain untouched.

Official references: [url_launcher](https://pub.dev/packages/url_launcher), [Admin SDK release notes](https://firebase.google.com/support/release-notes/admin/node), [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions).
