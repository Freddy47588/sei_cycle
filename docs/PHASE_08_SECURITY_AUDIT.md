# Phase 08 security and Admin readiness audit

Resumed verification: 24 October 2026 (Asia/Jakarta). Historical observations below retain their dates; final results are in the test and handoff reports.

Audit date: 17 October 2026, Asia/Jakarta. Source baseline: `f3380c3`, branch `feature/operational-v2`.

**Status: local security checks pass; production Admin acceptance is BLOCKED.** Current read-only inspection confirms the deployed Rules match the local candidate and all 96 expected composite indexes are READY. A production worker host, managed identity/IAM, monitoring and owner acceptance are still required. This audit did not deploy infrastructure, change production records or modify Authentication identities. Local fixtures use only loopback emulators and `demo-` projects.

## Finding fixed

The worker previously counted a second Admin profile with `is_active: false` as an available replacement when protecting the last active Admin. Its authorization check correctly rejected that same profile. A pure-function probe reproduced that archiving the only effective Admin was permitted.

`backend/admin/management.mjs` now uses the same active-Admin predicate for actor authorization and last-Admin protection, including both active-field aliases and deleted/reversed flags. Regression coverage checks archive, soft delete, role demotion and deactivation with unavailable replacement profiles, permits a usable legacy Admin replacement, and proves an emulator rejection retains the original profile and produces failure audit evidence without a backup/mutation.

This protects the effective **Firestore profile set**. Auth identities disabled or removed outside this workflow require owner reconciliation; no claim is made that every alternative Admin profile has a usable Auth login. Existing legacy role spellings must also be accepted by the deployed client Rules before they are relied on operationally.

## Education CRUD follow-up

The operational Education service uses atomic `education_contents` plus `education_edits` transactions directly; it does not require the Admin worker for create, edit, publication changes or soft deletion. Permanent removal through the generic Admin management panel still requires that worker. A real JavaScript SDK emulator probe using the service's full payload and audit structure passed for articles, videos and SOPs through create/edit/publish/archive/soft-delete. Sample-origin content can be corrected or hidden with exact audit evidence while retaining provenance. Field-operator creation is denied without partial writes. No Rules change or production deployment was needed.

The service did discard existing tags in video/SOP saves; both routes now retain supplied tags. It also accepts a stable creation request ID and recognizes an exact persisted payload when a committed response is lost, so retrying cannot create another content record or audit entry. Reusing that ID for a different payload fails without overwriting the saved content. Eight service regressions cover all three types, publication visibility, audit/rollback, response-failure retry and invalid IDs; these pass together with the existing Phase 07 tests (28 total). UI failure handling and preservation of the remaining form metadata are documented in the final audit.

## Architecture and evidence

| Boundary | Inspected implementation / verification | Result and limit |
| --- | --- | --- |
| Authentication | `AuthService` provides email/password login, registration, password reset and logout; Auth gate checks profile activity; read-only provider configuration has email/password enabled | Source/configuration verified; production login, mailbox delivery and each real role need device acceptance |
| Google entry points | Active authentication service and screens contain email/password paths | No Google sign-in entry point found in inspected auth source; this does not disable a provider in Firebase Console |
| Privileged requests | Immutable `admin_requests`, matching actor UID, pending initial state, server timestamp and Admin Rules checks | Matching local/deployed Rules; local tests verify clients cannot write completion status or delete receipts |
| Worker authorization | Production listener checks the Auth identity exists and is enabled; transaction rechecks active Admin profile | Source inspected; direct processor integration tests validate profile denial, while live listener/host behavior remains unverified |
| Exact target and fields | Root category/path allowlist, patch whitelists, type/range checks, canonical module IDs | Local plan tests; clients cannot set arbitrary stock or seed fields through worker patches |
| Preview freshness | Bounded transaction reads across all 17 categories; complete state hash; actor/operation/patch/reason match; ten-minute expiry | Emulator verifies stale dependency rejection; more than 500 records in any category rejects rather than silently truncates |
| Idempotency | Consumed previews, request receipts, deterministic reversal IDs, transactional mutation/audit/backup | Emulator verifies replay and Sale cancellation affect stock/income once |
| Stock and dependencies | Source reversal, complete balance/unit evidence, missing-parent rejection, reference graph, terminal inverse-pair restriction | Local plan and integration tests; no historical master or physical balance is recreated |
| Audit/recovery | Exact before/after snapshots in `admin_backups`, immutable `admin_audit`, tombstones, retained audit children | Matching local/deployed Rules deny client backup access and protected writes; emulator verifies recovery document presence |
| Identity lifecycle | Durable outbox, inactive pending profile, no UID adoption, separate identity audit, idempotent deletion | Real local Auth Emulator create/reset-link/delete test; interrupted `processing` jobs still require owner inspection |
| Recipient isolation | UID-specific messages, role broadcasts, recipient receipts, finance-recommendation isolation | Candidate Rules tests verify direct SDK denial and usable authorized queries |
| Trusted credentials | Worker requires production enable flag and managed Application Default Credentials | No service credential is embedded by this change; host/IAM approval and provisioning remain pending |

Server SDKs bypass Firestore Security Rules, so worker credentials require IAM protection independently of client Rules. This is a deployment requirement, not something a passing Rules suite establishes. See [Firebase Rules conditions](https://firebase.google.com/docs/firestore/security/rules-conditions) and [Admin user management](https://firebase.google.com/docs/auth/admin/manage-users).

## Seventeen-category capability matrix

All rows describe inspected local source and relevant local tests. **Worker-backed production mutations and category-by-category device acceptance remain unverified for every row.** The Admin client pages 20 records by exact document ID, searches loaded pages and routes operational creation to existing forms. Legacy collections remain explicit paths; creating a new canonical record does not recreate a legacy inventory master.

| Category | Create/read path | Correction and removal safeguards | Local evidence |
| --- | --- | --- | --- |
| `users` | Worker identity provisioning; paginated profiles | Name/role/activity; verified Auth workflow for identity removal; last Admin and tombstone protection; profile email cannot independently change Auth email | Last-Admin matrix; actor rejection; identity outbox and Auth Emulator |
| `farm_modules` | Worker canonical module form; Admin list | Metadata/activity; reviewed dependency-aware deletion | Metadata update/delete plan |
| `batches` | Existing Batch form; Admin list | Module/base-field changes require resolving active references; archive or unused deletion | Metadata and lifecycle/dependency plans; stale-preview transaction |
| `logbooks` | Existing five-module form; Admin list | Notes/title; quantities require source reversal and replacement; missing stock evidence blocks removal | Linked reversal and missing-effects tests |
| `inventory` | Existing master form; Admin list/history | Metadata/minimum; physical stock uses ledger; permanent removal requires verified zero and retains historical ledger | Metadata, zero-balance, missing-master and Sale reversal tests |
| `inventory_items` | Canonical form for new operations; explicit legacy list | Selected metadata; legacy removal requires verified zero; exact path prevents canonical ID collision | Legacy collision and metadata plans |
| `inventory_transactions` | Existing movement/correction form; Admin ledger | Notes; reverse manual/opening or source; only verified terminal adjacent inverse pair can be permanently removed | Source reversal and terminal-pair plans; immutable client-ledger Rules |
| `production_results` | Worker standalone form or Logbook; Admin list | Standalone corrections; linked result must resolve/reverse Logbook source | Metadata and linked-production denial plans |
| `schedules` | Existing Schedule form; Admin list | Status/date/title/type/notes; restore or dependency-aware removal; pending clears completion metadata | Metadata plans and schedule Rules suite |
| `finance_transactions` | Existing Finance form; Admin list | Manual amount/date/category; incremented version; linked Sale income requires Sale cancellation | Metadata plan; Sale atomicity/retry and Finance Rules |
| `finance_records` | Canonical Finance form for new entries; explicit legacy list | Selected amount/category/date/description; reviewed legacy deletion | Metadata update/delete plan |
| `sales` | Existing atomic Sales form; Admin list | Notes/buyer; quantity/price correction requires cancellation/replacement; verified stock/income reversal | Pure and emulator Sale cancellation/retry; paired-write Rules |
| `circular_flows` | Existing form; Admin list | Material/quantity/unit/date; resolve source quantities first; no invented stock effects | Metadata and no-invented-stock plans; flow Rules |
| `education_contents` | Existing content or worker form; all statuses for Admin | Article/video/SOP validation; draft/archive visibility; audit and reviewed removal | Metadata/unsafe URL plans; visibility and atomic edit-audit Rules |
| `notifications` | Worker form; Admin list/inbox | Body/title/category and UID/role targeting; receipts remain recipient-specific | Metadata plan and direct recipient/receipt isolation Rules |
| `recommendations` | Worker persisted form; Admin list | Title/reason/priority/module/resolution; source-generated recommendations regenerate from sources | Metadata plan and financial-isolation Rules |
| `report_metadata` | Worker form; Admin list | Selected name/title/type/description; dependency-aware archive/delete | Metadata update/delete plan |

The matrix does not equate metadata-plan tests with complete UI CRUD acceptance. Permanent removal can be intentionally rejected because of stock, source evidence, references or oversized graphs. Arbitrary business subcollections outside the inspected schema need an explicit graph/schema extension; immutable audit subcollections are retained.

## Candidate artifacts

| Artifact | Local identity |
| --- | --- |
| `firestore.rules` | SHA-256 `3b342ec640ec28fb9ea1bc5dd3b837dd6c4403e30adacf92f1d08acf48c98c93` |
| `firestore.indexes.json` | 96 composite indexes, zero field overrides; SHA-256 `8010e0299415f432da08dd2585505743c468f62dffd902c62e362a0b06f4ca14` |

No Rules/index implementation was changed by this security fix. A new Rules regression covers legacy-disabled Admin command/data denial. Separate current read-only production inspection establishes byte-identical deployed Rules, 96 READY composite indexes and no missing expected definition; this supersedes the historical Phase 07 statement that deployment was pending. Email/password authentication is enabled and the expected Android application is registered. Billing is disabled; host/cost decisions remain separate. See [the Firebase deployment report](PHASE_08_FIREBASE_DEPLOYMENT.md).

The live profile summary contains Admin and field-operator roles and an inactive profile; no finance-operator profile was available for runtime role acceptance. Account identifiers and counts are intentionally omitted. Empty inventory masters with retained orphaned ledger are a live integrity limitation, not evidence that all sample-origin data was deleted; this audit does not repair/recreate them.

## Executed verification

| Check | Actual result |
| --- | --- |
| Pre-fix pure-function probe | Reproduced last effective Admin deactivation with a legacy-disabled replacement |
| Baseline Admin tests | 34 passed; zero failed/skipped |
| Fixed Admin tests | 36 passed; zero failed/skipped; includes local Firestore/Auth integration |
| Matching local/deployed Rules suites | 175 passed; zero failed/skipped across Logbook/operations, updated Phase 07 and the five Education CRUD contract cases |
| `npm --prefix backend/admin audit --json` | Exit 0; zero known vulnerabilities reported by npm at audit time |
| `git diff --check` for security source/tests | Passed |

The npm audit result is bounded to the installed/locked dependency tree and advisory service at the audit time; it is not proof that the worker or every transitive dependency has no vulnerabilities. Runtime was Node 24.5.0, satisfying the worker's Node 22+ declaration. No package version was changed. Official release context: [Firebase Admin Node SDK releases](https://firebase.google.com/support/release-notes/admin/node).

Reproduction uses `firebase.phase07.json`, explicit `demo-seicycle-admin07`, loopback Firestore `8097` and Auth `9097`. Set `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST`, then run `npm --prefix backend/admin test` and `node --test tools/firestore_tests/phase07_rules.test.mjs tools/firestore_tests/logbook_rules.test.mjs tools/firestore_tests/phase08_education_rules.test.mjs`. In PowerShell, quote the combined emulator selector: `--only 'firestore,auth'`. Raw logs remain in ignored local storage. An initial interrupted emulator/test attempt is excluded from passing counts.

## Outstanding release gates

1. Owner-approved trusted host, managed service identity, least-privilege Firestore/Auth access, credentials management and supervision. Running the worker on a developer workstation is not a production deployment.
2. Preserve the now-verified deployed Rules/index artifacts, check old-client query compatibility and complete non-destructive runtime acceptance. Any future deployment still requires explicit owner approval; this audit did not deploy the matching artifacts.
3. Verify current usable Admin logins and every required production role without exposing account identifiers; obtain an approved finance-operator test identity. Verified email/password provider settings and local fixture role users do not prove live login/role acceptance.
4. Run staging acceptance for each category, request-listener failure/restart behavior, fresh/stale previews and backup recovery. The local backup test proves saved before/after evidence; it does not establish a full production restore rehearsal or restore Auth identities.
5. Define manual recovery for identity jobs left `processing` after a crash between Auth success and Firestore completion. Inspect exact job/UID/audit evidence before recovery; never blindly recreate an identity.
6. Complete real-device login/reset, cross-role denial, Admin preview/result and UAT evidence with the approved deployed architecture. Maintain production Admin status as blocked until these gates pass.

For rollback, retain reviewed prior Rules/index artifacts and stop request processing before reverting a failed worker rollout. A Rules rollback alone does not undo already committed business effects. Recover only an explicitly reviewed exact before/after manifest with its audit and dependency evidence; never bulk-replay backups or infer stock. Production restore, destructive corrections and identity recovery require their separate owner-approved scope.

## Continuation evidence ? 24 October

All 175 Rules and 36 Admin tests passed again with zero failures/skips. Read-only production verification still matches the Rules hash and all 96 indexes are READY. Canonical Inventory now has four masters; 22 historical ledger parent references remain unresolved. The task did not restore/delete business data or change Auth identities. Normal device-app initialization can update its own profile metadata; it is distinct from fixture/admin mutations. Production worker hosting/IAM/monitoring and full signed role acceptance remain unverified.
