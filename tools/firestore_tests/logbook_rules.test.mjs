import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection, query, where, orderBy, limit, startAfter, writeBatch, serverTimestamp, Timestamp, runTransaction, setLogLevel } from 'firebase/firestore';
setLogLevel('silent');
let env;
const now = Timestamp.fromMillis(1792108800000);
const entry = (id = 'entry') => ({ id, title: 'Pengamatan', moduleType: 'ayam_kampung', activityType: 'input_harian_ayam', activityDate: now, quantity: 0, unit: 'butir', status: 'completed', notes: 'Asli', details: { mortalitas_hari_ini: 0 }, createdBy: 'field', updatedBy: 'field', createdAt: now, updatedAt: now, isDeleted: false });
const dbFor = uid => env.authenticatedContext(uid).firestore();
before(async () => { env = await initializeTestEnvironment({ projectId: 'demo-seicycle-phase02', firestore: { host: '127.0.0.1', port: 8089, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } }); });
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async c => {
    const db = c.firestore();
    await Promise.all(Object.entries({ admin: 'admin', field: 'operator_lapangan', finance: 'operator_keuangan', reader: 'mitra', inactive: 'admin' }).map(([uid, role]) => setDoc(doc(db, 'users', uid), { id: uid, uid, role, isActive: uid !== 'inactive' })));
    await setDoc(doc(db, 'logbooks/entry'), entry());
  });
});
async function edit(db, uid = 'field', id = 'edit-1', patch = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, `logbooks/entry/note_edits/${id}`), { before: 'Asli', after: 'Diperbarui', editedBy: uid, editedAt: serverTimestamp() });
  batch.update(doc(db, 'logbooks/entry'), { notes: 'Diperbarui', updatedBy: uid, updatedAt: serverTimestamp(), lastNoteEditId: id, ...patch });
  return batch.commit();
}
for (const role of ['admin', 'field', 'finance', 'reader']) {
  test(`${role} can read logbook`, async () => { await assertSucceeds(getDoc(doc(dbFor(role), 'logbooks/entry'))); });
  test(`${role} create permission`, async () => {
    const data = { ...entry('new'), createdBy: role, updatedBy: role, createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
    await (['admin', 'field'].includes(role) ? assertSucceeds : assertFails)(setDoc(doc(dbFor(role), 'logbooks/new'), data));
  });
  test(`${role} audited note edit permission`, async () => { await (['admin', 'field'].includes(role) ? assertSucceeds : assertFails)(edit(dbFor(role), role)); });
  test(`${role} cannot modify quantities or delete`, async () => {
    const db = dbFor(role);
    await assertFails(edit(db, role, 'bad', { quantity: 9, details: { dedak_padi_kg: 7 } }));
    await assertFails(updateDoc(doc(db, 'logbooks/entry'), { isDeleted: true, updatedBy: role }));
    await assertFails(deleteDoc(doc(db, 'logbooks/entry')));
  });
}
test('anonymous and inactive users cannot read or write', async () => {
  for (const db of [env.unauthenticatedContext().firestore(), dbFor('inactive')]) {
    await assertFails(getDoc(doc(db, 'logbooks/entry')));
    await assertFails(setDoc(doc(db, 'logbooks/new'), entry('new')));
  }
});
test('unpaired note edit and forged audit are denied', async () => {
  const db = dbFor('field');
  await assertFails(updateDoc(doc(db, 'logbooks/entry'), { notes: 'x', updatedBy: 'field', updatedAt: serverTimestamp(), lastNoteEditId: 'missing' }));
  await assertFails(setDoc(doc(db, 'logbooks/entry/note_edits/orphan'), { before: 'Asli', after: 'x', editedBy: 'field', editedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, 'logbooks/entry'), { createdBy: 'admin', updatedBy: 'field' }));
});
test('audit cannot be rewritten or reused', async () => {
  const db = dbFor('field');
  await assertSucceeds(edit(db));
  await assertFails(updateDoc(doc(db, 'logbooks/entry/note_edits/edit-1'), { after: 'forged' }));
  await assertFails(deleteDoc(doc(db, 'logbooks/entry/note_edits/edit-1')));
  await assertFails(updateDoc(doc(db, 'logbooks/entry'), { notes: 'Diperbarui', updatedBy: 'field', updatedAt: serverTimestamp(), lastNoteEditId: 'edit-1' }));
});
test('atomic batch rolls back inventory when logbook operation is denied', async () => {
  const db = dbFor('field');
  const batch = writeBatch(db);
  batch.set(doc(db, 'inventory/feed'), { id: 'feed', currentStock: 5, createdBy: 'field', updatedBy: 'field', isDeleted: false });
  batch.update(doc(db, 'logbooks/entry'), { isDeleted: true, updatedBy: 'field' });
  await assertFails(batch.commit());
  assert.equal((await getDoc(doc(db, 'inventory/feed'))).exists(), false);
});
test('module/date queries page without repeated document IDs', async () => {
  await env.withSecurityRulesDisabled(async c => {
    for (let i = 0; i < 23; i++) await setDoc(doc(c.firestore(), 'logbooks', `page-${i}`), { ...entry(`page-${i}`), activityDate: now });
  });
  const db = dbFor('finance');
  const base = query(collection(db, 'logbooks'), where('isDeleted', '==', false), where('moduleType', '==', 'ayam_kampung'), where('activityDate', '>=', now), orderBy('activityDate', 'desc'), limit(20));
  const first = await getDocs(base);
  const second = await getDocs(query(base, startAfter(first.docs.at(-1))));
  assert.equal(first.size, 20); assert.equal(second.size, 4);
  assert.equal(new Set([...first.docs, ...second.docs].map(d => d.id)).size, 24);
});
test('concurrent transaction edits preserve conflict detection', async () => {
  async function change(uid, auditId) {
    const db = dbFor(uid);
    return runTransaction(db, async tx => {
      const ref = doc(db, 'logbooks/entry');
      const old = await tx.get(ref);
      if (old.data().notes !== 'Asli') throw new Error('conflict');
      tx.set(doc(db, `logbooks/entry/note_edits/${auditId}`), { before: 'Asli', after: uid, editedBy: uid, editedAt: serverTimestamp() });
      tx.update(ref, { notes: uid, updatedBy: uid, updatedAt: serverTimestamp(), lastNoteEditId: auditId });
    });
  }
  const results = await Promise.allSettled([change('field', 'one'), change('admin', 'two')]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  await env.withSecurityRulesDisabled(async c => { assert.equal((await getDocs(collection(c.firestore(), 'logbooks/entry/note_edits'))).size, 1); });
});
// Firestore SDK contract tests for the same multi-collection write shape used
// by the Dart service. The actual Dart method is exercised by the unit fake.
async function createOperational(db, uid, id, { deny = false } = {}) {
  try { return await runTransaction(db, async tx => {
    const ref = doc(db, 'logbooks', id);
    if ((await tx.get(ref)).exists()) return id;
    const feedRef = doc(db, 'inventory/logbook_dedak_padi');
    const eggsRef = doc(db, 'inventory/logbook_telur_ayam');
    const feed = await tx.get(feedRef);
    const eggs = await tx.get(eggsRef);
    const stocks = [[feedRef, feed, -5, 'kg'], [eggsRef, eggs, 3, 'butir']];
    tx.set(ref, { ...entry(id), details: { dedak_padi_kg: 5, produksi_telur_hari_ini: 3 }, createdBy: uid, updatedBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    for (const [stockRef, snapshot, delta, unit] of stocks) {
      const before = snapshot.data()?.currentStock ?? 0;
      tx.set(stockRef, { id: stockRef.id, itemKey: stockRef.id.slice(8), unit, currentStock: before + delta, minStock: 0, isLowStock: before + delta <= 0, createdBy: snapshot.data()?.createdBy ?? uid, createdAt: snapshot.data()?.createdAt ?? serverTimestamp(), updatedBy: uid, updatedAt: serverTimestamp(), isDeleted: false });
      tx.set(doc(db, 'inventory_transactions', `${id}-${stockRef.id}`), { id: `${id}-${stockRef.id}`, logbookId: id, itemId: stockRef.id, type: delta < 0 ? 'out' : 'in', quantity: Math.abs(delta), beforeStock: before, afterStock: before + delta, unit, createdBy: uid, createdAt: serverTimestamp(), transactionDate: serverTimestamp(), isReversed: false });
    }
    tx.set(doc(db, 'production_results', `${id}-eggs`), { id: deny ? 'wrong-id' : `${id}-eggs`, logbookId: id, quantity: 3, unit: 'butir', createdBy: uid, createdAt: serverTimestamp() });
    return id;
  }); } catch (error) {
    const committed = await getDoc(doc(db, 'logbooks', id));
    if (error.code === 'permission-denied' && committed.exists() && committed.data().createdBy === uid && committed.data().notes === 'Asli' && committed.data().details.dedak_padi_kg === 5 && committed.data().details.produksi_telur_hari_ini === 3) return id;
    throw error;
  }
}
test('operational creation retries same ID once across stock, transactions, production', async () => {
  const db = dbFor('field');
  const results = await Promise.all([createOperational(db, 'field', 'once'), createOperational(db, 'field', 'once')]);
  assert.deepEqual(results, ['once', 'once']);
  assert.equal((await getDoc(doc(db, 'inventory/logbook_dedak_padi'))).data().currentStock, -5);
  assert.equal((await getDoc(doc(db, 'inventory/logbook_telur_ayam'))).data().currentStock, 3);
  assert.equal((await getDocs(query(collection(db, 'inventory_transactions'), where('logbookId', '==', 'once')))).size, 2);
  assert.equal((await getDocs(query(collection(db, 'production_results'), where('logbookId', '==', 'once')))).size, 1);
});
test('concurrent entries atomically use current stock for multiple items', async () => {
  const db = dbFor('field');
  await Promise.all([createOperational(db, 'field', 'first'), createOperational(db, 'field', 'second')]);
  assert.equal((await getDoc(doc(db, 'inventory/logbook_dedak_padi'))).data().currentStock, -10);
  assert.equal((await getDoc(doc(db, 'inventory/logbook_telur_ayam'))).data().currentStock, 6);
});
test('denied production prevents partial inventory/logbook writes', async () => {
  const db = dbFor('field');
  await assertFails(createOperational(db, 'field', 'denied', { deny: true }));
  assert.equal((await getDoc(doc(db, 'logbooks/denied'))).exists(), false);
  assert.equal((await getDoc(doc(db, 'inventory/logbook_dedak_padi'))).exists(), false);
  assert.equal((await getDocs(collection(db, 'inventory_transactions'))).size, 0);
  assert.equal((await getDocs(collection(db, 'production_results'))).size, 0);
});
