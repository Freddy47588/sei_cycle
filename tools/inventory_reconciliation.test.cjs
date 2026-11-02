'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { inspectInventory, sanitizedInventory } = require('./inventory_reconciliation.cjs');
const completeCollections = ['inventory', 'inventory_items', 'inventory_transactions', 'logbooks', 'production_results', 'batches', 'sales', 'finance_transactions', 'finance_records'];
const doc = (path, data) => ({ path, data, updateTime: '2026-10-17T00:00:00Z' });
const master = () => doc('inventory/example', { createdBy: 'sample_seed', unit: 'kg', currentStock: 100, itemKey: 'example' });
const ledger = (patch = {}, id = 'one') => doc(`inventory_transactions/${id}`, { itemId: 'example', createdBy: 'operator', unit: 'kg', type: 'out', beforeStock: 100, quantity: 2, afterStock: 98, transactionDate: '2026-10-16T00:00:00Z', isReversed: false, ...patch });
const inspect = docs => inspectInventory({ completeCollections, documents: docs }, 'inventory/example');
test('seed balance and a genuine ledger never establish an opening balance', () => {
  const result = inspect([master(), ledger()]);
  assert.equal(result.status, 'awaiting_balance_confirmation');
  assert.equal(result.netMovement, -2);
  assert.equal(result.authoritativeBalance, null);
  assert.equal(result.verifiedOpeningBalance, null);
});
test('seed with no ledger remains unknown, not zero', () => {
  const result = inspect([master()]); assert.equal(result.authoritativeBalance, null); assert.equal(result.status, 'awaiting_balance_confirmation');
});
for (const [name, patch, code] of [
  ['bad quantity', { quantity: NaN }, 'invalid_ledger'],
  ['unit mismatch', { unit: 'liter' }, 'unit_mismatch'],
  ['missing logbook', { logbookId: 'missing' }, 'missing_reference'],
  ['reversal flag', { isReversed: true }, 'reversal_requires_evidence'],
  ['invalid equation', { afterStock: 97 }, 'stock_equation_conflict'],
  ['uncertain creator', { createdBy: '' }, 'uncertain_provenance'],
  ['invalid date', { transactionDate: 'tomorrow' }, 'invalid_chronology'],
]) test(name, () => assert.ok(inspect([master(), ledger(patch)]).issues.some(i => i.code === code)));
test('duplicate retries and missing continuity are detected', () => {
  const result = inspect([master(), ledger({ requestId: 'request' }), ledger({ requestId: 'request' }, 'two')]);
  assert.ok(result.issues.some(i => i.code === 'duplicate_logical_event'));
  assert.ok(result.issues.some(i => i.code === 'ledger_chain_gap'));
});
test('soft-deleted master and ambiguous legacy identity are conflicts', () => {
  const m = master(); m.data.isDeleted = true;
  const result = inspect([m, doc('inventory_items/example', { current_stock: 9 })]);
  assert.ok(result.issues.some(i => i.code === 'soft_deleted'));
  assert.ok(result.issues.some(i => i.code === 'duplicated_inventory_identity'));
});
test('sale/finance and production dependencies are retained without copying', () => {
  const result = inspect([master(), ledger({ logbookId: 'log' }), doc('logbooks/log', { createdBy: 'operator' }),
    doc('production_results/harvest', { logbookId: 'log' }), doc('sales/sale', { inventoryItemId: 'example', financeTransactionId: 'cash' }),
    doc('finance_transactions/cash', { saleId: 'sale', amount: 1234 })]);
  assert.equal(result.dependencies.length, 6); assert.equal(result.authoritativeBalance, null);
});
test('snapshot mutation invalidates preview fingerprint', () => {
  const docs = [master(), ledger()]; const first = inspect(docs).fingerprint;
  docs[1].updateTime = '2026-10-17T01:00:00Z'; assert.notEqual(inspect(docs).fingerprint, first);
});
test('scope must include canonical and legacy sources', () => assert.throws(() => inspectInventory({ completeCollections: ['inventory'], documents: [master()] }, 'inventory/example')));
test('sanitized output has no document paths, names, actors or quantities', () => {
  const summary = sanitizedInventory({ completeCollections, documents: [master(), ledger({ notes: 'private note' })] });
  const text = JSON.stringify(summary); for (const secret of ['private note', 'operator', 'inventory/example', 'netMovement', 'currentStock', '100']) assert.ok(!text.includes(secret));
  assert.equal(summary.realLedgerCount, 1);
});
