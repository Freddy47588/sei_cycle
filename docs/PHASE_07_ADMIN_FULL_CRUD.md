# Phase 07 — Controlled Admin management

17 October 2026, Asia/Jakarta. Baseline `8e9f888`, branch `feature/operational-v2`.

## Actual status

The app has a **Kelola Data Admin** destination under Lainnya/sidebar and a trusted Node worker in `backend/admin`. The worker and candidate Rules/indexes are **not deployed**. Existing production clients retain existing production authorization. New privileged actions require the reviewed Rules/index deployment and a running trusted worker; a button alone does not establish production capability.

The local implementation provides exact-path selection, 20-record pages, search of loaded pages, refresh, detail inspection, explicit field forms, reason entry, dependency checking, affected-document preview, confirmation, request history and verified result feedback. The panel includes legacy collections even when optional index fields are missing. Credentials are excluded from its record inspector. Normal operational creation forms remain accessible from the panel. It never offers a global database-delete action.

## Capability matrix

“Worker” below means implemented locally and pending production deployment. The test suite includes collection-specific mutation-plan coverage; the cross-document integration cases are listed separately. It is not a claim of real-device CRUD acceptance for every row.

| Business data | Create / read | Administrative correction | Removal path and constraints |
| --- | --- | --- | --- |
| User profiles | Worker email-identity provisioning; paginated profiles | Name, role, active state; last active Admin protected | Deactivate, remove profile, or explicitly remove profile plus Auth identity through durable outbox; UID tombstone prevents self-registration from recreating a removed profile |
| Farm modules | Worker form; canonical new module ID | Name, description, active state | Archive/deactivate or reviewed permanent deletion |
| Batches | Existing Batch form; Admin list | Name, location, dates, status, initial population/unit and module when references permit | Archive completed/active batch; delete unused batch; resolve active dependents first |
| Logbooks | Existing five-module form; Admin list | Title/notes directly; quantities corrected by reversing source effects and recording a replacement | Plain unused record may be removed; linked record must reverse verified ledger/production first |
| Inventory masters | Existing master form; Admin list/history | Metadata/minimum/classification; explicit physical correction through existing ledger form, with reason | Archive, restore, or permanent removal only at a verified zero balance; historical ledger retained |
| Legacy inventory | Canonical form for new operations; exact legacy-path list | Selected legacy metadata/minimum | Delete specific zero-balance legacy record; no ID collision with canonical collection |
| Inventory transactions | Existing stock movement/correction form; Admin ledger list | Notes; reverse manual/opening transactions or their Logbook/Sale source | Original plus terminal adjacent inverse may be deleted together after balance/reference checks; later activity requires a separately reviewed exact manifest |
| Production results | Worker standalone production form or existing Logbook form | Standalone quantities/quality/date; linked production via Logbook reversal and replacement | Linked result cannot be removed independently; reversed/standalone record may be removed after dependencies resolve |
| Schedules | Existing form; Admin list | Dates/status/title/type/notes, including completed/skipped records | Soft delete, restore or permanent removal after references resolve; local reminders cancel on next synchronization |
| Finance transactions | Existing Finance form; Admin list | Manual values/date/category with version increment and protected before/after backup | Soft/permanent delete manual records; sale income follows Sale cancellation first |
| Legacy finance | Canonical form for new records; exact legacy-path list | Selected values/category/date/description | Selected legacy deletion after dependency checks |
| Sales | Existing atomic Sales form; Admin list | Notes/buyer directly; quantity, price or payment correction by cancellation and new sale | Atomic stock reversal + income removal + cancelled receipt; permanent receipt removal after safe resolution |
| Circular flows | Existing form; Admin list | Actual material/quantity/unit/date/notes; referenced quantities require source resolution | Reviewed archive/soft/permanent deletion; no invented stock movements |
| Education | Existing article/video/SOP form or worker form; all statuses for Admin | Publication/content/module/type fields | Archive, soft delete, reviewed permanent delete |
| Notifications | Worker form; Admin list/inbox | Message, category and UID/role targeting | Archive/soft/permanent delete; no automatic publication or duplicate alert on delete |
| Persisted recommendations | Worker form; Admin list | Reason/title/priority/module/resolved status | Archive/soft/permanent delete; on-demand recommendations are regenerated from actual sources |
| Report metadata | Worker form; Admin list | Name/title/type/description | Archive/soft/permanent delete after reference checks |

Legacy records are not rewritten when read. Missing `createdBy` does not imply sample provenance. Newly created operational records cannot set seed metadata through the worker whitelist. Existing reference/amount evidence is never replaced with guessed values.

## Trusted authorization and transactions

Clients can create immutable `admin_requests/{requestId}` only as an authenticated active Admin, with `actorUid == request.auth.uid`. They cannot write worker results, backup contents, tombstones, identity jobs or protected audit logs. The worker rechecks the effective Admin profile in its transaction. In production its request listener additionally checks that the Auth identity still exists and is not disabled.

Preview and execution independently read all 17 supported root collections inside a server transaction. A sentinel rejects collections above 500 records rather than treating a partial graph as complete. The canonical/legacy reference graph includes linked batches, Logbooks, ledger, production, schedules, sales, finance, notifications and recommendations. The preview records a hash of the complete bounded state. Execution requires the same actor, operation, patch and reason, an unused preview no older than ten minutes, and the same state hash. A concurrent change—including a newly inserted dependency—requires a new preview.

The worker commits writes/deletions, an immutable `admin_audit` result, exact before/after recovery documents in `admin_backups`, tombstones and request completion atomically. Failed requests receive protected failure evidence. Request IDs and consumed previews prevent replay. Backup data stays server-only; ordinary Admin management cannot erase it. Existing immutable note/finance-edit subcollections are retained at their original paths when a parent is removed; no recursive deletion of audit children occurs.

Stock reversals validate original before/after/quantity/unit evidence and current master stock. Missing masters, inconsistent deltas, duplicate reversal, active references to source effects or a negative resulting balance reject the whole operation. Sale cancellation requires the exact matching finance and ledger records. An orphaned historical ledger never causes a master or physical balance to be recreated. Cancelled sales/production no longer contribute to operational totals; reversed ledger remains readable even after its cancelled source is removed.

Permanent ledger cleanup is deliberately narrower than source cancellation: only a verified terminal, adjacent inverse pair can be removed together, with the previous balance reference restored. Intervening stock activity cannot be silently rewritten. Such historical cases need additional evidence and an exact reviewed manifest, not an unconditional client delete permission.

## Identity outbox and recovery

Auth and Firestore cannot share an atomic transaction. Profile provisioning creates an inactive `identityPending` profile and a protected identity job. The worker creates the Auth user and records a separate identity audit, then clears the pending flag; activation remains a distinct reviewed Admin action. UID/email collisions fail closed. Profile-only removal leaves the Auth identity intact; **Hapus profil dan identitas Auth (bertahap)** explicitly requests both.

Identity deletion tolerates `auth/user-not-found`. The UI waits for identity completion and shows `needs_review` instead of a false success. A transaction claims each identity job so concurrent workers cannot perform the same job twice. A worker crash after Auth succeeds but before Firestore completion can leave `processing`; an owner must inspect the exact UID, Auth result and audit/job state before recovering that job. It must not blindly create a replacement identity or replay identity creation. No credentials, password hashes or reset links are persisted in business records.

## Deployment gate — not executed

1. Review candidate Rules, the three new composite indexes and impact on existing clients. Role/deactivation/profile deletion now use the worker; education drafts and UID-targeted notifications receive server-side isolation. Old inbox queries lacking `userId == ''` for broadcasts require an app update. Direct production-result deletion is closed.
2. Choose an owner-managed trusted host, Node 22+ and managed Application Default Credentials. Grant only the Firestore/Auth permissions required by the worker and protect recovery data through IAM. Do not distribute Admin credentials in the APK or repository. No paid service, billing plan or Cloud Function is enabled by this change.
3. In that trusted environment run `npm ci --prefix backend/admin --ignore-scripts`. Review the locked official Firebase Admin SDK and transitive warnings before production rollout.
4. After explicit deployment approval, deploy the reviewed artifacts with `firebase deploy --only firestore:rules,firestore:indexes --project seicycle-kebun-sei` and wait for indexes to become ready. This command is documentation, not an action performed in Phase 07.
5. Start the reviewed worker with `GCLOUD_PROJECT=seicycle-kebun-sei` and `SEICYCLE_ADMIN_WORKER_ENABLED=true`; configure credentials outside source control. Maintain a single supervised worker initially and monitor pending/processing/needs_review requests. Review cost/host decisions separately.
6. Verify non-destructive preview/auth boundaries and a staging restore rehearsal before enabling real destructive operations. Every production destructive action still requires its exact in-app preview and explicit confirmation. Development never executes production deletion.

## Emulator reproduction and limits

`firebase.phase07.json` provides Firestore at `127.0.0.1:8097` and Auth at `127.0.0.1:9097`, with separate local hub/logging ports. Always select a `demo-` project. Run `firebase emulators:start --only firestore,auth --project demo-seicycle-admin07 --config firebase.phase07.json`, set `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` to those endpoints, then run `npm --prefix backend/admin test`. Rules suites are `node --test tools/firestore_tests/phase07_rules.test.mjs` and `npm --prefix tools/firestore_tests test`.

Phase 07 tests also reused the existing demo Firestore endpoint `127.0.0.1:8095`; all destructive fixtures were local. Tests cover stale previews, rollback, replay, missing source/master, sale/logbook reversal, exact legacy paths, last-Admin protection, backup/tombstones, source-effect dependencies, metadata plans and real Auth Emulator provisioning/reset-link/deletion.

Pending production capabilities are precisely the worker host/credentials/monitoring and reviewed Rules/index rollout. Missing historical saldo/source evidence and oversized dependency graphs remain record-specific blockers. Arbitrary deep business subcollections not present in the inspected schema require an explicit schema extension; audit subcollections are preserved. Full category-by-category real-device acceptance, process-crash recovery rehearsal and complete release QA remain unverified; do not describe production Admin Full CRUD as completed before these gates.

References: [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions), [Admin user management](https://firebase.google.com/docs/auth/admin/manage-users), [official Admin SDK releases](https://firebase.google.com/support/release-notes/admin/node).
