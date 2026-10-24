# Phase 08 — Firebase rollout and recovery

Resumed verification: 24 October 2026 (Asia/Jakarta). Historical observations below retain their dates; final results are in the test and handoff reports.

17 October 2026, Asia/Jakarta. **Read-only state verified; production Admin acceptance BLOCKED.** No Firebase deployment, billing change, business-data mutation or Auth identity change was performed by this phase.

## Observed state

| Check | Fresh evidence |
| --- | --- |
| Project / database | `seicycle-kebun-sei` / `(default)`, Firestore Native, `asia-southeast2` |
| Android registration | Expected `id.seicycle.app` package is registered |
| Authentication configuration | Email enabled with password required; this does not prove delivery of reset emails or each account login |
| Deployed Rules | Byte-identical to repository `firestore.rules`; SHA-256 `3b342ec640ec28fb9ea1bc5dd3b837dd6c4403e30adacf92f1d08acf48c98c93` |
| Source index file | SHA-256 `8010e0299415f432da08dd2585505743c468f62dffd902c62e362a0b06f4ca14`, 96 composites, zero overrides |
| Live indexes | All 96 READY; paginated read compared collection group, scope and indexed fields, ignoring implicit document-name ordering; no candidate definition missing |
| Billing | Read-only billing API reports billing disabled |
| Worker | Source/emulator verified; host, runtime identity, IAM, uptime, monitoring and production request acceptance unverified |

This supersedes the Phase 07 historical statement that Rules/indexes were pending. It does not establish who deployed them or when. Source equality and index readiness do not prove that a trusted worker is running.

The **17 October** bounded read-only snapshot enumerated 202 root documents across 16 roots. Inventory masters remained empty; 22 historical stock ledger records referenced missing masters. Seed-origin records remained in other collections. No balance was inferred and no retired master/sample data was recreated. Raw documents, identities, amounts, Rules responses and audit logs remain private under ignored local storage. An empty root does not prove all sample data was removed.

## Refreshed read-only snapshot ? 24 October

The new complete root snapshot contains **219 documents across 17 roots**: canonical Inventory now has four masters, Logbook 21 documents, Education 11 contents plus four edit records, and stock ledger 26 records. Twenty-two ledger records still reference missing historical masters; 24 seed-origin documents remain elsewhere. These are observed changes since the earlier snapshot, not data created/repaired by this audit. No physical balance was inferred.

Rules remain byte-identical, every one of the 96 expected indexes is READY, Android registration/email-password configuration still match, and billing remains disabled. CLI read credentials were used only in memory; raw responses remain private. This refresh does not establish a running Admin worker.

## Client and Education compatibility

Operational Education CRUD uses direct authorized Firestore transactions with matching immutable `education_edits`, before/after states and server timestamps. It does **not** need the worker. The Phase 08 UI fixes an intrinsic-layout exception that prevented opening its form, retains failed inputs, and preserves metadata. Five real-emulator Rules cases validate article/video/SOP lifecycle, historical provenance preservation and unauthorized write denial. No Rules weakening/deployment was needed for that fix.

The generic Admin category, permanent deletions, stock/finance reversals and identity jobs need the worker. Old clients without atomic Education audit, recipient broadcast receipts or current Admin requests may fail under the current Rules. Coordinate client upgrades; do not restore permissive historical Rules to make an old client work.

## Owner decisions before worker activation

1. Select an existing trusted supervised Node ≥22 host and an operational owner. Billing-disabled Firebase does not itself provide a persistent Node worker. No unapproved paid resource was provisioned.
2. Establish managed Application Default Credentials and least-privilege access. The worker needs business and request reads, transaction writes, protected backup/audit writes and explicitly reviewed Auth user lifecycle permissions. Prefer a custom scoped role to broad project Owner/Editor; verify effective permissions on the selected host. A Firebase CLI user session is not automatically worker ADC.
3. Configure automatic restart, single intended project, health checks, alerting for listener failure, old pending requests, failed requests and `processing`/`needs_review` identity jobs. Avoid logging payloads/credentials. Review worker listener error handling with the supervisor.
4. Approve cost, audit retention, backup/restore objectives and recovery ownership. Current host/IAM and backup restoration have not been proven by this task.

## Controlled sequence

1. Record deployed Rules/index fingerprints again; preserve approved prior Rules and manifests privately. Pause privileged requests during rollout. Do not use a partial query as a recovery manifest.
2. Obtain a consistent protected business backup, required audit/identity evidence and a tested emulator/staging restoration rehearsal. Check retention, encryption, access and operator responsibilities. The diagnostic snapshot alone is not an accepted recovery system.
3. Review [security capability matrix](PHASE_08_SECURITY_AUDIT.md), dependency caveats and the exact worker commit. The complete graph rejects roots over 500 documents, uncertain balance evidence, unsupported child schemas and stale previews.
4. If Rules/indexes change in a future rollout, obtain explicit deployment approval and review the diff. Candidate command, **not executed by Phase 08**:

   ```bash
   firebase deploy --only firestore:rules,firestore:indexes --project seicycle-kebun-sei
   ```

5. Verify exact deployed Rules source and every required index READY after any approved deploy. Current matching artifacts need no redeployment merely to apply Flutter fixes.
6. On the approved trusted host, install locked worker dependencies, set `GCLOUD_PROJECT=seicycle-kebun-sei`, `SEICYCLE_ADMIN_WORKER_ENABLED=true` and managed ADC, then start `node backend/admin/worker.mjs` under the supervisor.
7. First perform a harmless read/list and non-destructive preview using an approved Admin test account. Verify exact actor, target, state hash, expiry and request completion. Fixture mutation/reversal/delete acceptance belongs in staging/emulators.
8. Verify all intended roles, new client Education lifecycle against approved test content, recipient isolation and account deactivation. Obtain owner acceptance before declaring Full CRUD available in production.

No production preview request was submitted by this audit, so it cannot claim worker-offline detection or live completion.

## Rollback and recovery

- Stop the worker supervisor/listeners first to prevent more privileged execution; record pending/completed request IDs privately. Do not delete requests/audits to hide a failure.
- Roll back the client only to a version compatible with the active Rules. Restore prior Rules only after a separate security review/approval; never use open access as rollback.
- Restore business data only from verified exact-path backup manifests with dependency checks and a rehearsal. Stock reversal and financial pairs remain atomic; do not reconstruct missing physical balances or restore only one side of a sale.
- Auth and Firestore cannot share a transaction. Inspect exact UID, identity job and audit state before recovering `processing`/`needs_review`. Never adopt an unrelated account by matching email or blindly replay creation after an uncertain response.
- Keep protected audit history immutable. A compensating correction is preferable to erasing evidence. Owner must authorize irreversible production recovery actions.

**Exit gate:** host/IAM/supervisor evidence, approved backups/recovery, live preview acceptance and role UAT are still required. Local emulator success is evidence for implementation, not production hosting.
