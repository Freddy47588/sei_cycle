'use strict';
// Pure, offline reconciliation analysis. Never infers an opening/physical balance.
const crypto = require('node:crypto');
const REFERENCES = { itemId: 'inventory', inventoryItemId: 'inventory', logbookId: 'logbooks',
  batchId: 'batches', sourceBatchId: 'batches', destinationBatchId: 'batches', saleId: 'sales',
  inventoryTransactionId: 'inventory_transactions', financeTransactionId: 'finance_transactions' };
const creator = d => d.createdBy ?? d.created_by;
const seed = d => creator(d) === 'sample_seed';
const deleted = d => d.isDeleted === true || d.is_deleted === true;
const review = d => !seed(d) && (d.isSampleData === true || d.sampleVersion === 'v2');
const finite = n => typeof n === 'number' && Number.isFinite(n) && Math.abs(n) <= 1e12;
const equal = (a, b) => Math.abs(a - b) <= Math.max(1, Math.abs(a), Math.abs(b)) * 1e-10;
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, stable(value[k])]));
  return value;
}
const digest = value => crypto.createHash('sha256').update(JSON.stringify(stable(value))).digest('hex');
function inspectInventory(snapshot, sourcePath) {
  if (!/^inventory(?:_items)?\/[^/]+$/.test(sourcePath)) throw new Error('Invalid inventory source');
  for (const c of ['inventory', 'inventory_items', 'inventory_transactions', 'logbooks', 'production_results', 'batches', 'sales', 'finance_transactions', 'finance_records']) {
    if (!snapshot.completeCollections?.includes(c)) throw new Error('Incomplete reconciliation scope');
  }
  const byPath = new Map(snapshot.documents.map(d => [d.path, d]));
  if (byPath.size !== snapshot.documents.length) throw new Error('Duplicate document path');
  const master = byPath.get(sourcePath);
  if (!master) throw new Error('Inventory source missing');
  const id = sourcePath.split('/')[1];
  const issues = [];
  const add = (code, paths) => issues.push({ code, paths });
  const allLedger = snapshot.documents.filter(d => d.path.startsWith('inventory_transactions/') && d.data.itemId === id)
    .sort((a, b) => String(a.data.transactionDate).localeCompare(String(b.data.transactionDate)) || a.path.localeCompare(b.path));
  const ledger = allLedger.filter(d => !seed(d.data));
  const logIds = new Set(ledger.map(d => d.data.logbookId).filter(Boolean));
  const sales = snapshot.documents.filter(d => d.path.startsWith('sales/') && d.data.inventoryItemId === id && !seed(d.data));
  const saleIds = new Set(sales.map(d => d.path.split('/')[1]));
  const results = snapshot.documents.filter(d => d.path.startsWith('production_results/') &&
    (logIds.has(d.data.logbookId) || d.data.inventoryItemId === id || d.data.itemId === id) && !seed(d.data));
  const related = new Map([[master.path, master], ...allLedger.map(d => [d.path, d]), ...sales.map(d => [d.path, d]), ...results.map(d => [d.path, d])]);
  for (const d of snapshot.documents) {
    const c = d.path.split('/')[0];
    if ((c === 'logbooks' && logIds.has(d.path.split('/')[1])) ||
      (['finance_transactions', 'finance_records'].includes(c) && saleIds.has(d.data.saleId)) ||
      (c === 'notifications' && d.data.relatedId === id)) related.set(d.path, d);
  }
  const visited = new Set();
  function visit(doc) {
    if (visited.has(doc.path)) return;
    visited.add(doc.path);
    if (deleted(doc.data)) add('soft_deleted', [doc.path]);
    if (review(doc.data)) add('uncertain_provenance', [doc.path]);
    for (const [field, collection] of Object.entries(REFERENCES)) {
      const ref = doc.data[field];
      if (ref == null || ref === '') continue;
      if (typeof ref !== 'string' || ref.includes('/')) { add('invalid_reference', [doc.path]); continue; }
      let parent = byPath.get(`${collection}/${ref}`);
      if (!parent && collection === 'inventory') parent = byPath.get(`inventory_items/${ref}`);
      if (!parent) { add('missing_reference', [doc.path, `${collection}/${ref}`]); continue; }
      if (seed(parent.data) && parent.path !== sourcePath && !seed(doc.data)) add('other_seed_reference', [doc.path, parent.path]);
      if (!related.has(parent.path)) related.set(parent.path, parent);
      visit(parent);
    }
  }
  // Do not let illustrative seed history create a false operational dependency.
  for (const doc of [...related.values()]) if (!seed(doc.data) || doc.path === sourcePath) visit(doc);
  const events = new Map();
  let netMovement = 0;
  let movementValid = true;
  for (const entry of ledger) {
    const d = entry.data;
    if (!creator(d)) add('uncertain_provenance', [entry.path]);
    if (d.unit !== master.data.unit) add('unit_mismatch', [entry.path]);
    const date = Date.parse(d.transactionDate);
    if (!Number.isFinite(date)) add('invalid_chronology', [entry.path]);
    if (d.isReversed === true) add('reversal_requires_evidence', [entry.path]);
    if (!['in', 'out', 'opening', 'correction'].includes(d.type) ||
      ![d.quantity, d.beforeStock, d.afterStock].every(finite) || d.quantity < 0) {
      add('invalid_ledger', [entry.path]); movementValid = false; continue;
    }
    const delta = d.type === 'correction' ? d.afterStock - d.beforeStock : d.type === 'out' ? -d.quantity : d.quantity;
    if (!equal(d.beforeStock + delta, d.afterStock) || (d.type === 'correction' && !equal(Math.abs(delta), d.quantity))) add('stock_equation_conflict', [entry.path]);
    netMovement += delta;
    const event = d.requestId || d.logbookId;
    if (event) {
      const key = JSON.stringify([event, d.itemId, d.type]);
      if (events.has(key)) add('duplicate_logical_event', [events.get(key), entry.path]);
      events.set(key, entry.path);
    }
  }
  for (let i = 1; i < allLedger.length; i++) {
    const a = allLedger[i - 1], b = allLedger[i];
    if (finite(a.data.afterStock) && finite(b.data.beforeStock) && !equal(a.data.afterStock, b.data.beforeStock)) add('ledger_chain_gap', [a.path, b.path]);
  }
  const peers = snapshot.documents.filter(d => ['inventory', 'inventory_items'].includes(d.path.split('/')[0]) && d.path !== sourcePath &&
    (d.path.split('/')[1] === id || (d.data.itemKey && d.data.itemKey === master.data.itemKey)));
  if (peers.length) add('duplicated_inventory_identity', peers.map(d => d.path));
  const dependencies = [...related.values()].sort((a, b) => a.path.localeCompare(b.path));
  return { sourcePath, seedOrigin: seed(master.data), legacySource: sourcePath.startsWith('inventory_items/'),
    status: issues.length ? 'conflict' : 'awaiting_balance_confirmation',
    issues, ledger, allLedger, dependencies, verifiedOpeningBalance: null, authoritativeBalance: null,
    // A net movement is NOT a stock balance; the UI must label it accordingly.
    netMovement: movementValid ? netMovement : null,
    fingerprint: digest(dependencies.map(d => ({ path: d.path, updateTime: d.updateTime, data: d.data }))) };
}
function sanitizedInventory(snapshot) {
  const masters = snapshot.documents.filter(d => d.path.startsWith('inventory/') && seed(d.data)).sort((a, b) => a.path.localeCompare(b.path));
  const rows = masters.map((m, i) => {
    const result = inspectInventory(snapshot, m.path);
    return { reviewItem: i + 1, realLedgerCount: result.ledger.length, seedLedgerCount: result.allLedger.length - result.ledger.length,
      relatedLogbooks: result.dependencies.filter(d => d.path.startsWith('logbooks/') && !seed(d.data)).length,
      relatedProductionResults: result.dependencies.filter(d => d.path.startsWith('production_results/') && !seed(d.data)).length,
      status: result.status, issueCodes: [...new Set(result.issues.map(i => i.code))].sort(),
      verifiedOpeningBalance: null, authoritativeBalance: null };
  });
  return { capturedAtUtc: snapshot.capturedAtUtc, source: 'targeted read-only refresh', rows,
    seedMasters: rows.length, realLedgerCount: rows.reduce((n, r) => n + r.realLedgerCount, 0),
    mastersWithRealActivity: rows.filter(r => r.realLedgerCount > 0).length,
    deterministicBalancesVerified: 0, productionWrites: 0 };
}
module.exports = { inspectInventory, sanitizedInventory, seed, deleted, review, finite, digest, stable, REFERENCES };
if (require.main === module) {
  const fs = require('node:fs');
  const snapshot = JSON.parse(fs.readFileSync('build/stabilization/reconciliation-snapshot.json', 'utf8'));
  fs.writeFileSync('build/stabilization/reconciliation-readiness.json', JSON.stringify(sanitizedInventory(snapshot), null, 2));
  console.log(JSON.stringify(sanitizedInventory(snapshot)));
}
