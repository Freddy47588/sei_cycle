import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, getCountFromServer, collection, query, where, orderBy, limit, startAfter, writeBatch, serverTimestamp, Timestamp, runTransaction, setLogLevel } from 'firebase/firestore';
setLogLevel('silent');
async function retryTransaction(db, body) {
  for (let attempt = 0; ; attempt++) {
    try { return await runTransaction(db, body); }
    catch (e) { if (attempt >= 2 || !['permission-denied','aborted'].includes(e.code)) throw e; }
  }
}
let env;
const [emulatorHost, emulatorPort] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8089').split(':');
const now = Timestamp.fromMillis(1792108800000);
const entry = (id = 'entry') => ({ id, title: 'Pengamatan', moduleType: 'ayam_kampung', activityType: 'input_harian_ayam', activityDate: now, quantity: 0, unit: 'butir', status: 'completed', notes: 'Asli', details: { mortalitas_hari_ini: 0 }, createdBy: 'field', updatedBy: 'field', createdAt: now, updatedAt: now, isDeleted: false });
const dbFor = uid => env.authenticatedContext(uid).firestore();
before(async () => { env = await initializeTestEnvironment({ projectId: 'demo-seicycle-phase02', firestore: { host: emulatorHost, port: Number(emulatorPort), rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } }); });
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
    return retryTransaction(db, async tx => {
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
  try { return await retryTransaction(db, async tx => {
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
      tx.set(stockRef, { id: stockRef.id, name: stockRef.id.slice(8), category: 'operasional', moduleType: 'ayam_kampung', location: '', lastTransactionId: `${id}-${stockRef.id}`, itemKey: stockRef.id.slice(8), unit, currentStock: before + delta, minStock: 0, isLowStock: before + delta <= 0, createdBy: snapshot.data()?.createdBy ?? uid, createdAt: snapshot.data()?.createdAt ?? serverTimestamp(), updatedBy: uid, updatedAt: serverTimestamp(), isDeleted: false });
      tx.set(doc(db, 'inventory_transactions', `${id}-${stockRef.id}`), { id: `${id}-${stockRef.id}`, itemName: stockRef.id.slice(8), itemKey: stockRef.id.slice(8), moduleType: 'ayam_kampung', notes: 'Otomatis dari logbook', source: 'logbook', requestId: id, logbookId: id, itemId: stockRef.id, type: delta < 0 ? 'out' : 'in', quantity: Math.abs(delta), beforeStock: before, afterStock: before + delta, unit, createdBy: uid, createdAt: serverTimestamp(), transactionDate: serverTimestamp(), isReversed: false });
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

// Phase 03: batches use globally unique normalized code as document ID.
const batchData = (id = 'KOLAM-A', uid = 'field', patch = {}) => ({
  id, code: id, name: 'Kolam A', moduleType: 'lele', locationName: 'Kolam Utara',
  status: 'planned', startedAt: now, expectedHarvestAt: null, completedAt: null,
  initialQuantity: 500, initialUnit: 'ekor', commodity: '', notes: '',
  createdBy: uid, updatedBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  isDeleted: false, ...patch,
});
async function seedBatch(patch = {}) {
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'batches/KOLAM-A'), batchData('KOLAM-A', 'field', { status: 'active', ...patch })));
}
const batchedEntry = (id = 'batched', patch = {}) => ({ ...entry(id), moduleType: 'lele', batchId: 'KOLAM-A', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...patch });
for (const uid of ['admin', 'field', 'finance', 'reader']) {
  test(`phase03 ${uid} batch read and create/update permissions`, async () => {
    await seedBatch(); const db = dbFor(uid);
    await assertSucceeds(getDoc(doc(db, 'batches/KOLAM-A')));
    const check = ['admin', 'field'].includes(uid) ? assertSucceeds : assertFails;
    await check(setDoc(doc(db, 'batches/NEW-CODE'), batchData('NEW-CODE', uid)));
    await check(updateDoc(doc(db, 'batches/KOLAM-A'), { name: 'Nama baru', updatedBy: uid, updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(db, 'batches/KOLAM-A')));
  });
}
test('phase03 anonymous and inactive users denied batch access', async () => {
  await seedBatch();
  for (const db of [env.unauthenticatedContext().firestore(), dbFor('inactive')]) {
    await assertFails(getDoc(doc(db, 'batches/KOLAM-A')));
    await assertFails(setDoc(doc(db, 'batches/NEW-CODE'), batchData('NEW-CODE')));
  }
});
test('phase03 five official modules and optional quantities allowed', async () => {
  const db = dbFor('field');
  for (const [n, moduleType] of ['ayam_kampung', 'maggot_bsf', 'cacing_tanah', 'tanaman', 'lele'].entries()) {
    await assertSucceeds(setDoc(doc(db, `batches/MODULE-${n}`), batchData(`MODULE-${n}`, 'field', { moduleType, initialQuantity: null, initialUnit: '' })));
  }
});
test('phase03 malformed batches and forged audit identities rejected', async () => {
  const db = dbFor('field');
  for (const patch of [{name: ''}, {name: '   '}, {name: '\t'}, {locationName: '   '}, {locationName: ''}, {moduleType: 'fish'}, {code: 'DIFFERENT'}, {initialQuantity: -1}, {initialQuantity: 1, initialUnit: ''}, {expectedHarvestAt: Timestamp.fromMillis(1)}, {status: 'active'}, {completedAt: now}, {createdBy: 'admin'}, {updatedBy: 'admin'}, {createdAt: now}, {updatedAt: now}, {isDeleted: true}, {extra: 'field'}]) {
    await assertFails(setDoc(doc(db, 'batches/KOLAM-A'), batchData('KOLAM-A', 'field', patch)));
  }
});
test('phase03 immutable cycle identity and initial baseline protected even from admin', async () => {
  await seedBatch(); const db = dbFor('admin');
  for (const patch of [{moduleType: 'tanaman'}, {code: 'NEW-CODE'}, {startedAt: Timestamp.fromMillis(1)}, {initialQuantity: 9}, {initialUnit: 'kg'}, {createdBy: 'admin'}, {createdAt: now}, {isDeleted: true}, {completedAt: now}]) {
    await assertFails(updateDoc(doc(db, 'batches/KOLAM-A'), { ...patch, updatedBy: 'admin', updatedAt: serverTimestamp() }));
  }
});
test('phase03 forward lifecycle records server completion and archives without deleting history', async () => {
  const db = dbFor('field'), ref = doc(db, 'batches/KOLAM-A');
  await setDoc(ref, batchData());
  const audit = {updatedBy: 'field', updatedAt: serverTimestamp()};
  await assertFails(updateDoc(ref, {...audit, status: 'completed', completedAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(ref, {...audit, status: 'active'}));
  await assertFails(updateDoc(ref, {...audit, status: 'completed', completedAt: now}));
  await assertSucceeds(updateDoc(ref, {...audit, status: 'completed', completedAt: serverTimestamp()}));
  const completion = (await getDoc(ref)).data().completedAt;
  await assertFails(updateDoc(ref, {...audit, status: 'active', completedAt: null}));
  await assertFails(updateDoc(ref, {...audit, name: 'Rewrite completed'}));
  await assertSucceeds(updateDoc(ref, {...audit, status: 'archived'}));
  assert.ok((await getDoc(ref)).data().completedAt.isEqual(completion));
  await assertFails(deleteDoc(ref));
});
test('phase03 active matching batch accepted and legacy batchless create retained', async () => {
  await seedBatch(); const db = dbFor('field');
  await assertSucceeds(setDoc(doc(db, 'logbooks/batched'), batchedEntry()));
  await assertSucceeds(setDoc(doc(db, 'logbooks/general'), {...entry('general'), createdAt: serverTimestamp(), updatedAt: serverTimestamp()}));
  assert.equal((await getDoc(doc(db, 'logbooks/entry'))).data().batchId, undefined);
});
for (const [name, patch] of [['wrong module', {moduleType:'tanaman'}], ['planned', {status:'planned'}], ['completed', {status:'completed', completedAt:now}], ['archived', {status:'archived', completedAt:now}], ['deleted', {isDeleted:true}]]) {
  test(`phase03 logbook rejects ${name} batch`, async () => {
    await seedBatch(patch); await assertFails(setDoc(doc(dbFor('field'), 'logbooks/batched'), batchedEntry()));
  });
}
test('phase03 missing batch, null batch and batch reassignment denied', async () => {
  const db = dbFor('field');
  await assertFails(setDoc(doc(db, 'logbooks/batched'), batchedEntry()));
  await assertFails(setDoc(doc(db, 'logbooks/batched'), batchedEntry('batched', {batchId: null})));
  await seedBatch(); await setDoc(doc(db, 'logbooks/batched'), batchedEntry());
  await assertFails(updateDoc(doc(db, 'logbooks/batched'), {batchId: 'OTHER', updatedBy:'field', updatedAt:serverTimestamp()}));
});
test('phase03 batch status checked after all writes: cannot complete and append logbook atomically', async () => {
  await seedBatch(); const db = dbFor('field'), writes = writeBatch(db);
  writes.update(doc(db, 'batches/KOLAM-A'), {status:'completed', completedAt:serverTimestamp(), updatedBy:'field', updatedAt:serverTimestamp()});
  writes.set(doc(db, 'logbooks/batched'), batchedEntry());
  await assertFails(writes.commit());
  assert.equal((await getDoc(doc(db, 'batches/KOLAM-A'))).data().status, 'active');
});
test('phase03 concurrent code reservation has one winner without overwrites', async () => {
  const db = dbFor('field'), ref = doc(db, 'batches/UNIQUE');
  const create = () => retryTransaction(db, async tx => {
    if ((await tx.get(ref)).exists()) throw new Error('duplicate code');
    tx.set(ref, batchData('UNIQUE')); return ref.id;
  });
  const results = await Promise.allSettled([create(), create()]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal((await getDoc(ref)).data().code, 'UNIQUE');
});
test('phase03 completion racing logbook transaction aborts without stock side effects', async () => {
  await seedBatch(); const db = dbFor('field');
  let markRead, release;
  const hasRead = new Promise(r => {markRead = r;});
  const ready = new Promise(r => {release = r;});
  const save = retryTransaction(db, async tx => {
    const batch = await tx.get(doc(db, 'batches/KOLAM-A'));
    if (batch.data().status !== 'active') throw new Error('batch inactive');
    markRead(); await ready;
    tx.set(doc(db, 'logbooks/batched'), batchedEntry());
    tx.set(doc(db, 'inventory/race'), {id:'race', currentStock:3, createdBy:'field', updatedBy:'field', isDeleted:false});
  });
  const rejected = assert.rejects(save, error => error.message.includes('batch inactive') || error.code === 'permission-denied');
  await hasRead;
  await updateDoc(doc(db, 'batches/KOLAM-A'), {status:'completed', completedAt:serverTimestamp(), updatedBy:'field', updatedAt:serverTimestamp()});
  release(); await rejected;
  assert.equal((await getDoc(doc(db, 'logbooks/batched'))).exists(), false);
  assert.equal((await getDoc(doc(db, 'inventory/race'))).exists(), false);
});
test('phase03 batch and activity queries page with filters and tied timestamps', async () => {
  await env.withSecurityRulesDisabled(async c => {
    for (let n = 0; n < 23; n++) {
      await setDoc(doc(c.firestore(), `batches/PAGE-${n}`), batchData(`PAGE-${n}`, 'field', {status:'active'}));
      await setDoc(doc(c.firestore(), `logbooks/activity-${n}`), batchedEntry(`activity-${n}`));
    }
  });
  const db = dbFor('reader');
  for (const base of [query(collection(db, 'batches'), where('isDeleted','==',false), where('moduleType','==','lele'), where('status','==','active'), orderBy('createdAt','desc'), limit(20)), query(collection(db,'logbooks'), where('isDeleted','==',false), where('batchId','==','KOLAM-A'), orderBy('activityDate','desc'),limit(20))]) {
    const first = await getDocs(base), second = await getDocs(query(base, startAfter(first.docs.at(-1))));
    assert.equal(first.size,20); assert.equal(second.size,3);
    assert.equal(new Set([...first.docs,...second.docs].map(d=>d.id)).size,23);
  }
});

// Phase 04 contract: atomic inventory ledger and operational checklist.
const stockData = (id = 'feed', stock = 20) => ({id, name: 'Pakan', itemKey: 'pakan',
  moduleType: 'lele', category: 'pakan', unit: 'kg', location: 'Gudang',
  currentStock: stock, minStock: 5, isLowStock: stock <= 5, isDeleted: false,
  createdBy: 'field', updatedBy: 'field', createdAt: now, updatedAt: now});
async function seedStock(stock = 20) {
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'inventory/feed'), stockData('feed', stock)));
}
const ledgerData = (id, before = 20, value = 10, type = 'in', uid = 'field', patch = {}) => {
  const after = type === 'correction' ? value : type === 'out' ? before - value : before + value;
  return {id, requestId: id, itemId: 'feed', itemName: 'Pakan', itemKey: 'pakan',
    moduleType: 'lele', type, quantity: type === 'correction' ? Math.abs(after - before) : value,
    requestedValue: value, unit: 'kg', beforeStock: before, afterStock: after, notes: 'Stock opname',
    source: 'manual', allowNegative: false, batchId: null, transactionDate: serverTimestamp(),
    createdBy: uid, createdAt: serverTimestamp(), isReversed: false, ...patch};
};
async function mutate(db, id, {value = 10, type = 'in', uid = 'field', patch = {}, stockPatch = {}} = {}) {
  return retryTransaction(db, async tx => {
    const history = doc(db, 'inventory_transactions', id), item = doc(db, 'inventory/feed');
    const old = await tx.get(history);
    if (old.exists()) {
      if (old.data().requestedValue !== value || old.data().type !== type || old.data().createdBy !== uid) throw new Error('Request ID payload berbeda');
      return id;
    }
    const current = await tx.get(item);
    const data = ledgerData(id, current.data().currentStock, value, type, uid, patch);
    tx.update(item, {currentStock: data.afterStock, isLowStock: data.afterStock <= current.data().minStock,
      lastTransactionId: id, updatedBy: uid, updatedAt: serverTimestamp(), ...stockPatch});
    tx.set(history, data);
    return id;
  });
}
test('phase04 stock in 20+10, out 30-5, absolute correction 25->23 and one history each', async () => {
  await seedStock(); const db = dbFor('field');
  await mutate(db, 'in'); await mutate(db, 'out', {type: 'out', value: 5});
  await mutate(db, 'correct', {type: 'correction', value: 23});
  assert.equal((await getDoc(doc(db, 'inventory/feed'))).data().currentStock, 23);
  const h = (await getDoc(doc(db, 'inventory_transactions/correct'))).data();
  assert.equal(h.beforeStock, 25); assert.equal(h.afterStock, 23); assert.equal(h.quantity, 2);
  assert.equal((await getDocs(collection(db, 'inventory_transactions'))).size, 3);
});
test('phase04 identical request retries once; different payload rejected', async () => {
  await seedStock(); const db = dbFor('field');
  await mutate(db, 'once'); await mutate(db, 'once');
  await assert.rejects(mutate(db, 'once', {value: 9}), /payload berbeda/);
  assert.equal((await getDoc(doc(db, 'inventory/feed'))).data().currentStock, 30);
  assert.equal((await getDocs(collection(db, 'inventory_transactions'))).size, 1);
});
test('phase04 concurrent operators serialize without lost updates', async () => {
  await seedStock();
  await Promise.all([mutate(dbFor('field'), 'a'), mutate(dbFor('admin'), 'b', {uid: 'admin', value: 5})]);
  assert.equal((await getDoc(doc(dbFor('field'), 'inventory/feed'))).data().currentStock, 35);
});
for (const uid of ['admin', 'field', 'finance', 'reader', 'inactive']) {
  test(`phase04 ${uid} inventory and schedule authorization`, async () => {
    await seedStock(); const db = dbFor(uid);
    const read = uid === 'inactive' ? assertFails : assertSucceeds;
    await read(getDoc(doc(db, 'inventory/feed')));
    const allowed = ['admin','field'].includes(uid) ? assertSucceeds : assertFails;
    await allowed(mutate(db, `role-${uid}`, {uid}));
    await allowed(setDoc(doc(db, 'schedules/role'), scheduleData('role', uid)));
  });
}
test('phase04 anonymous stock, history and schedules rejected', async () => {
  await seedStock(); const db = env.unauthenticatedContext().firestore();
  for (const path of ['inventory/feed', 'inventory_transactions/a', 'schedules/role']) await assertFails(getDoc(doc(db, path)));
  await assertFails(mutate(db, 'anon'));
});
test('phase04 legacy operator writes and legacy reader remains read-only', async () => {
  await seedStock();
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'users/legacy'), {role: 'operator', isActive: true}));
  await assertSucceeds(mutate(dbFor('legacy'), 'legacy', {uid: 'legacy'}));
  await assertFails(mutate(dbFor('reader'), 'reader', {uid: 'reader'}));
});
test('phase04 admin and field cannot directly write stock or forge immutable master identity', async () => {
  await seedStock();
  for (const uid of ['field', 'admin']) {
    const db = dbFor(uid);
    for (const patch of [{currentStock: 100}, {currentStock: 100, lastTransactionId: 'missing'},
      {unit: 'liter'}, {itemKey: 'other'}, {moduleType: 'tanaman'}, {createdBy: uid}, {createdAt: serverTimestamp()}, {id: 'other'}]) {
      if (patch.createdBy === 'field') continue;
      await assertFails(updateDoc(doc(db, 'inventory/feed'), {...patch, updatedBy: uid, updatedAt: serverTimestamp()}));
    }
  }
});
test('phase04 metadata keeps stock and computes low flag; ledger is immutable', async () => {
  await seedStock(); const db = dbFor('field');
  await assertSucceeds(updateDoc(doc(db, 'inventory/feed'), {name: 'Pakan Baru', minStock: 25, isLowStock: true, location: 'Gudang B', updatedBy: 'field', updatedAt: serverTimestamp()}));
  assert.equal((await getDoc(doc(db, 'inventory/feed'))).data().currentStock, 20);
  await assertFails(updateDoc(doc(db, 'inventory/feed'), {isLowStock: false, updatedBy: 'field', updatedAt: serverTimestamp()}));
});
test('phase04 invalid unit, NaN, infinity, actor, audit, reversal and mismatched paired stock fail atomically', async () => {
  await seedStock(); const db = dbFor('field');
  const patches = [{unit: 'liter'}, {quantity: NaN}, {quantity: Infinity}, {createdBy: 'admin'},
    {createdAt: now}, {transactionDate: now}, {isReversed: true}, {reversedBy: 'field'},
    {itemId: 'another'}, {itemName: 'Forged'}, {beforeStock: 3}, {quantity: -1}, {notes: ''}, {logbookId: 'entry'}];
  for (const [i, patch] of patches.entries()) await assertFails(mutate(db, `bad-${i}`, {patch}));
  await assertFails(mutate(db, 'bad-stock', {stockPatch: {currentStock: 99}}));
  assert.equal((await getDoc(doc(db, 'inventory/feed'))).data().currentStock, 20);
  assert.equal((await getDocs(collection(db, 'inventory_transactions'))).size, 0);
});
test('phase04 stock minus requires explicit permission and absolute correction stays nonnegative', async () => {
  await seedStock(2); const db = dbFor('field');
  await assertFails(mutate(db, 'negative', {type: 'out', value: 5}));
  await assertSucceeds(mutate(db, 'negative', {type: 'out', value: 5, patch: {allowNegative: true}}));
  await assertFails(mutate(db, 'bad-correction', {type: 'correction', value: -4, patch: {allowNegative: true}}));
  await assertSucceeds(mutate(db, 'correction', {type: 'correction', value: 0}));
});
test('phase04 history cannot be overwritten, reversed or deleted even by admin, or added without paired item', async () => {
  await seedStock(); const db = dbFor('admin');
  await mutate(db, 'audit', {uid: 'admin'});
  for (const patch of [{notes: 'erase'}, {quantity: 99}, {isReversed: true}, {createdBy: 'field'}]) await assertFails(updateDoc(doc(db, 'inventory_transactions/audit'), patch));
  await assertFails(deleteDoc(doc(db, 'inventory_transactions/audit')));
  await assertFails(setDoc(doc(db, 'inventory_transactions/unpaired'), ledgerData('unpaired', 30, 1, 'in', 'admin')));
  await assertFails(updateDoc(doc(db, 'inventory/feed'), {currentStock: 40, lastTransactionId: 'audit', updatedBy: 'admin', updatedAt: serverTimestamp()}));
});
test('phase04 opening stock must have atomic opening ledger; retry cannot overwrite', async () => {
  const db = dbFor('field'), ref = doc(db, 'inventory/new');
  const data = {...stockData('new', 10), createdAt: serverTimestamp(), updatedAt: serverTimestamp(), lastTransactionId: 'opening_new'};
  await assertFails(setDoc(ref, data));
  const batch = writeBatch(db); batch.set(ref, data);
  const h = {...ledgerData('opening_new', 0, 10), itemId: 'new', requestId: 'new', type: 'opening', source: 'opening'};
  delete h.batchId; delete h.allowNegative; delete h.requestedValue;
  batch.set(doc(db, 'inventory_transactions/opening_new'), h);
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(ref, {...data, currentStock: 50}));
});
test('phase04 zero stock creation and zero-only admin soft deletion retain history', async () => {
  const db = dbFor('admin'), ref = doc(db, 'inventory/zero');
  await assertSucceeds(setDoc(ref, {...stockData('zero', 0), createdBy: 'admin', updatedBy: 'admin', createdAt: serverTimestamp(), updatedAt: serverTimestamp()}));
  await assertFails(deleteDoc(ref));
  await assertSucceeds(updateDoc(ref, {isDeleted: true, updatedBy: 'admin', updatedAt: serverTimestamp()}));
  await seedStock();
  await assertFails(updateDoc(doc(db, 'inventory/feed'), {isDeleted: true, updatedBy: 'admin', updatedAt: serverTimestamp()}));
});
test('phase04 history filters and timestamp cursor include all matching rows', async () => {
  await seedStock(); const db = dbFor('field');
  for (let i = 0; i < 3; i++) await mutate(db, `page-${i}`);
  const q = query(collection(db, 'inventory_transactions'), where('itemId', '==', 'feed'), orderBy('transactionDate', 'desc'), limit(2));
  const first = await getDocs(q), next = await getDocs(query(q, startAfter(first.docs.at(-1))));
  assert.equal(first.size, 2); assert.equal(next.size, 1);
  assert.equal((await getDocs(query(collection(db, 'inventory_transactions'), where('source', '==', 'manual'), orderBy('transactionDate', 'desc')))).size, 3);
});
const scheduleData = (id = 'task', uid = 'field', patch = {}) => ({id, title: 'Pemberian pakan', moduleType: 'lele',
  type: 'pakan', date: now, status: 'pending', notes: '', batchId: null, isDeleted: false,
  createdBy: uid, updatedBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...patch});
async function seedSchedule(patch = {}) {
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'schedules/task'), scheduleData('task', 'field', patch)));
}
async function finish(db, status = 'done', uid = 'field') {
  return retryTransaction(db, async tx => {
    const ref = doc(db, 'schedules/task'), old = await tx.get(ref);
    if (old.data().status === status) return;
    if (old.data().status !== 'pending') throw new Error('Status berubah');
    tx.update(ref, {status, updatedBy: uid, updatedAt: serverTimestamp(),
      ...(status === 'done' ? {completedBy: uid, completedAt: serverTimestamp()} : {skippedBy: uid, skippedAt: serverTimestamp(), skipReason: 'Hujan'})});
  });
}
test('phase04 schedule active matching batch accepted; missing, planned, completed, archived, deleted or mismatch rejected', async () => {
  const db = dbFor('field');
  await seedBatch();
  await assertSucceeds(setDoc(doc(db, 'schedules/valid'), scheduleData('valid', 'field', {batchId: 'KOLAM-A'})));
  for (const patch of [{moduleType: 'ayam_kampung'}, {status: 'planned'}, {status: 'completed'}, {status: 'archived'}, {isDeleted: true}]) {
    await seedBatch(patch);
    await assertFails(setDoc(doc(db, 'schedules/invalid'), scheduleData('invalid', 'field', {batchId: 'KOLAM-A'})));
  }
  await assertFails(setDoc(doc(db, 'schedules/missing'), scheduleData('missing', 'field', {batchId: 'MISSING'})));
});
test('phase04 legacy schedule without batch can be read and completed after batch is closed', async () => {
  await seedSchedule(); const db = dbFor('field');
  await env.withSecurityRulesDisabled(c => updateDoc(doc(c.firestore(), 'schedules/task'), {batchId: 'KOLAM-A'}));
  await seedBatch({status: 'completed'});
  await assertSucceeds(getDoc(doc(db, 'schedules/task')));
  await assertSucceeds(finish(db));
});
test('phase04 done records actor and timestamp once; repeated taps do not replace first completion', async () => {
  await seedSchedule(); const db = dbFor('field');
  await finish(db); const before = (await getDoc(doc(db, 'schedules/task'))).data();
  await finish(dbFor('admin'), 'done', 'admin');
  const after = (await getDoc(doc(db, 'schedules/task'))).data();
  assert.equal(after.completedBy, 'field'); assert(after.completedAt.isEqual(before.completedAt));
  assert.equal((await getDocs(collection(db, 'inventory_transactions'))).size, 0);
  assert.equal((await getDocs(collection(db, 'logbooks'))).size, 1);
});
test('phase04 skipped records actor, reason and timestamp; stale opposite status cannot overwrite', async () => {
  await seedSchedule(); const db = dbFor('field'); await finish(db, 'skipped');
  const data = (await getDoc(doc(db, 'schedules/task'))).data();
  assert.equal(data.skippedBy, 'field'); assert.equal(data.skipReason, 'Hujan'); assert(data.skippedAt instanceof Timestamp);
  await assert.rejects(finish(db, 'done'), /Status berubah/);
  await assertFails(updateDoc(doc(db, 'schedules/task'), {status: 'pending', updatedBy: 'field', updatedAt: serverTimestamp()}));
});
test('phase04 simultaneous conflicting checklist decisions preserve one terminal state', async () => {
  await seedSchedule(); const db = dbFor('field');
  const results = await Promise.allSettled([finish(db), finish(dbFor('admin'), 'skipped', 'admin')]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const d = (await getDoc(doc(db, 'schedules/task'))).data();
  assert(['done','skipped'].includes(d.status));
});
test('phase04 forged schedule audit, direct terminal create, arbitrary fields and missing completion rejected', async () => {
  await seedSchedule(); const db = dbFor('admin');
  for (const patch of [{createdBy: 'admin'}, {createdAt: serverTimestamp()}, {completedBy: 'admin'},
    {status: 'done'}, {status: 'done', completedBy: 'field', completedAt: serverTimestamp()},
    {status: 'done', completedBy: 'admin', completedAt: now}, {status: 'skipped'}, {arbitrary: 'field'}]) {
    await assertFails(updateDoc(doc(db, 'schedules/task'), {...patch, updatedBy: 'admin', updatedAt: serverTimestamp()}));
  }
  await assertFails(setDoc(doc(db, 'schedules/terminal'), scheduleData('terminal', 'admin', {status: 'done'})));
});
test('phase04 schedule edit updates time, validates batch and retains creator; only admin soft deletes pending', async () => {
  await seedSchedule(); const db = dbFor('field');
  await assertSucceeds(updateDoc(doc(db, 'schedules/task'), {date: Timestamp.fromMillis(now.toMillis()+3600000), updatedBy: 'field', updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(db, 'schedules/task'), {batchId: 'MISSING', updatedBy: 'field', updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(db, 'schedules/task'), {isDeleted: true, updatedBy: 'field', updatedAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(dbFor('admin'), 'schedules/task'), {isDeleted: true, updatedBy: 'admin', updatedAt: serverTimestamp()}));
  await assertFails(deleteDoc(doc(dbFor('admin'), 'schedules/task')));
});
test('phase04 schedule status/date/batch queries paginate and filter', async () => {
  await seedBatch(); const db = dbFor('field');
  for (let i=0;i<3;i++) await setDoc(doc(db, `schedules/q-${i}`), scheduleData(`q-${i}`, 'field', {batchId:'KOLAM-A'}));
  const q = query(collection(db, 'schedules'), where('isDeleted','==',false), where('status','==','pending'), where('batchId','==','KOLAM-A'), where('date','<', Timestamp.fromMillis(now.toMillis()+1)), orderBy('date'), limit(2));
  const first=await getDocs(q), next=await getDocs(query(q,startAfter(first.docs.at(-1))));
  assert.equal(first.size,2); assert.equal(next.size,1);
});

test('phase04 largest chicken logbook with four inventory items, batch and alerts fits Rules access budget', async () => {
  await seedBatch({moduleType:'ayam_kampung'}); const db=dbFor('field');
  await assertSucceeds(retryTransaction(db, async tx => {
    const id='max-items', log=doc(db,'logbooks',id);
    const actions=[['dedak_padi',5,'out','kg'],['talas_pepaya',2,'out','kg'],['maggot_segar',1,'out','kg'],['telur_ayam',3,'in','butir']];
    const refs=actions.map(([key]) => doc(db,'inventory',`logbook_${key}`));
    for(const ref of refs) await tx.get(ref);
    tx.set(log,{...entry(id),batchId:'KOLAM-A',createdBy:'field',updatedBy:'field',createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
    for(const [i,[key,qty,type,unit]] of actions.entries()) {
      const tid=`${id}-${key}`,after=type==='out'?-qty:qty;
      tx.set(refs[i],{...stockData(refs[i].id,after), name:key,itemKey:key,moduleType:'ayam_kampung',unit,lastTransactionId:tid,createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
      tx.set(doc(db,'inventory_transactions',tid),{id:tid,requestId:id,itemId:refs[i].id,itemName:key,itemKey:key,moduleType:'ayam_kampung',
        logbookId:id,batchId:'KOLAM-A',type,quantity:qty,unit,beforeStock:0,afterStock:after,notes:'Otomatis dari logbook',source:'logbook',
        transactionDate:serverTimestamp(),createdBy:'field',createdAt:serverTimestamp(),isReversed:false});
      if(type==='out') tx.set(doc(db,'notifications',`low_stock_field_${refs[i].id}`),{id:`low_stock_field_${refs[i].id}`,title:'Stok rendah',body:'Saat diperiksa',
        type:'low_stock',targetRole:'admin',userId:'field',relatedCollection:'inventory',relatedId:refs[i].id,isRead:false,createdAt:serverTimestamp(),isDeleted:false});
    }
    tx.set(doc(db,'production_results',id),{id,logbookId:id,batchId:'KOLAM-A',quantity:3,unit:'butir',createdBy:'field',createdAt:serverTimestamp()});
  }));
  assert.equal((await getDocs(query(collection(db,'inventory_transactions'),where('logbookId','==','max-items')))).size,4);
});

test('phase04 unknown role and conflicting inactive legacy flag cannot read operational data', async () => {
  await seedStock(); await seedSchedule();
  for(const [uid,profile] of [['unknown',{role:'unknown',isActive:true}], ['legacy-inactive',{role:'admin',isActive:true,is_active:false}]]) {
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'users',uid),profile));
    const db=dbFor(uid);
    for(const path of ['inventory/feed','inventory_transactions/missing','schedules/task']) await assertFails(getDoc(doc(db,path)));
  }
});

// Phase 05: UI hiding is insufficient; test direct get, query, and aggregate access.
for (const uid of ['admin', 'finance', 'field', 'reader', 'inactive', null]) {
  test(`phase05 finance read protection: ${uid ?? 'anonymous'}`, async () => {
    await env.withSecurityRulesDisabled(async c => {
      await setDoc(doc(c.firestore(), 'finance_transactions/cash'), {
        id: 'cash', type: 'income', amount: 25000, date: now, isDeleted: false
      });
    });
    const db = uid ? dbFor(uid) : env.unauthenticatedContext().firestore();
    const check = ['admin', 'finance'].includes(uid) ? assertSucceeds : assertFails;
    await check(getDoc(doc(db, 'finance_transactions/cash')));
    await check(getDocs(query(collection(db, 'finance_transactions'), where('isDeleted', '==', false), limit(10))));
    await check(getCountFromServer(query(collection(db, 'finance_transactions'), where('isDeleted', '==', false))));
  });
}
test('phase05 dashboard count and batch productivity query contracts', async () => {
  const db = dbFor('field');
  const q = query(collection(db, 'logbooks'), where('isDeleted', '==', false),
    where('moduleType', '==', 'ayam_kampung'), where('batchId', '==', 'cycle'),
    where('activityDate', '>=', now), orderBy('activityDate', 'desc'), limit(501));
  await assertSucceeds(getDocs(q));
  const count = await assertSucceeds(getCountFromServer(query(collection(db, 'logbooks'),
    where('isDeleted', '==', false), where('activityDate', '>=', now))));
  assert.equal(count.data().count, 1);
  await assertSucceeds(getDocs(query(collection(db, 'production_results'), where('moduleType', '==', 'lele'),
    where('batchId', '==', 'cycle'), where('harvestDate', '>=', now), orderBy('harvestDate', 'desc'), limit(501))));
});

// Phase 06: client SDK contracts, with rules active for all four sale writes.
async function seedHarvest(stock = 20, patch = {}) {
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'inventory/harvest'), {
    ...stockData('harvest', stock), name: 'Lele Panen', itemKey: 'lele_panen',
    category: 'hasil_panen', productType: 'harvest', isSellable: true, ...patch}));
}
function saleWrites(db, uid, id, before, {quantity = 5, unitPrice = 25000, salePatch = {}, ledgerPatch = {},
  financePatch = {}, itemPatch = {}, omit = ''} = {}) {
  const lid = `sale_${id}`, total = Math.round(quantity * unitPrice);
  const sale = {id, requestId: id, saleNumber: `S-${id}`, creationPayload: JSON.stringify([quantity, unitPrice]),
    inventoryItemId: 'harvest', productName: 'Lele Panen', moduleType: 'lele', quantity,
    quantityMilli: Math.round(quantity * 1000), unit: 'kg', unitPrice, totalAmount: total,
    buyerName: '', paymentMethod: 'tunai', saleDate: now, notes: '', status: 'paid',
    inventoryTransactionId: lid, financeTransactionId: lid, createdBy: uid, updatedBy: uid,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...salePatch};
  const ledger = {id: lid, requestId: id, saleId: id, itemId: 'harvest', itemName: 'Lele Panen',
    itemKey: 'lele_panen', moduleType: 'lele', type: 'out', source: 'sale', quantity, unit: 'kg',
    beforeStock: before, afterStock: before - quantity, notes: `Penjualan S-${id}`,
    transactionDate: serverTimestamp(), createdAt: serverTimestamp(), createdBy: uid, isReversed: false, ...ledgerPatch};
  const finance = {id: lid, requestId: id, saleId: id, source: 'sale', type: 'income',
    category: 'Penjualan hasil panen', amount: total, date: now, description: `Penjualan S-${id}`,
    notes: `Penjualan S-${id}`, paymentMethod: 'tunai', moduleType: 'lele', isDeleted: false,
    version: 0, createdBy: uid, updatedBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...financePatch};
  const stock = {currentStock: before - quantity, isLowStock: before - quantity <= 5,
    lastTransactionId: lid, updatedBy: uid, updatedAt: serverTimestamp(), ...itemPatch};
  return writer => {
    if (omit !== 'sale') writer.set(doc(db, `sales/${id}`), sale);
    if (omit !== 'stock') writer.update(doc(db, 'inventory/harvest'), stock);
    if (omit !== 'ledger') writer.set(doc(db, `inventory_transactions/${lid}`), ledger);
    if (omit !== 'finance') writer.set(doc(db, `finance_transactions/${lid}`), finance);
  };
}
async function commitSale(id, options = {}, uid = 'admin') {
  const db = dbFor(uid);
  return retryTransaction(db, async tx => {
    await tx.get(doc(db, `users/${uid}`));
    const prior = await tx.get(doc(db, `sales/${id}`));
    const payload = JSON.stringify([options.quantity ?? 5, options.unitPrice ?? 25000]);
    if (prior.exists()) { if (prior.data().creationPayload !== payload) throw Error('payload conflict'); return id; }
    const stock = await tx.get(doc(db, 'inventory/harvest'));
    await tx.get(doc(db, `inventory_transactions/sale_${id}`));
    await tx.get(doc(db, `finance_transactions/sale_${id}`));
    if (stock.data().currentStock < (options.quantity ?? 5)) throw Error('insufficient stock');
    saleWrites(db, uid, id, stock.data().currentStock, options)(tx); return id;
  });
}
test('phase06 sale 20kg - 5kg - 8kg = 7kg, income once, no production write', async () => {
  await seedHarvest();
  await commitSale('one'); await commitSale('two', {quantity: 8}); await commitSale('one');
  const db = dbFor('admin');
  assert.equal((await getDoc(doc(db, 'inventory/harvest'))).data().currentStock, 7);
  assert.equal((await getDocs(collection(db, 'sales'))).size, 2);
  const cash = await getDocs(collection(db, 'finance_transactions'));
  assert.equal(cash.docs.reduce((sum,d) => sum+d.data().amount, 0), 325000);
  assert.equal((await getDocs(collection(db, 'inventory_transactions'))).size, 2);
  assert.equal((await getDocs(collection(db, 'production_results'))).size, 0);
  await assert.rejects(commitSale('one', {quantity: 6}));
});
test('phase06 concurrent sale of 8 from 10kg allows only one paid receipt', async () => {
  await seedHarvest(10);
  const results = await Promise.allSettled([commitSale('race1', {quantity: 8}), commitSale('race2', {quantity: 8})]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal((await getDoc(doc(dbFor('admin'), 'inventory/harvest'))).data().currentStock, 2);
  assert.equal((await getDocs(collection(dbFor('admin'), 'finance_transactions'))).size, 1);
});
test('phase06 same simultaneous request has one stock decrement and receipt', async () => {
  await seedHarvest();
  await Promise.all([commitSale('same'), commitSale('same')]);
  assert.equal((await getDoc(doc(dbFor('admin'), 'inventory/harvest'))).data().currentStock, 15);
  assert.equal((await getDocs(collection(dbFor('admin'), 'sales'))).size, 1);
});
for (const omit of ['sale','stock','ledger','finance']) {
  test(`phase06 missing ${omit} fails without partial writes`, async () => {
    await seedHarvest(); const db = dbFor('admin'), batch = writeBatch(db);
    saleWrites(db, 'admin', 'partial', 20, {omit})(batch);
    await assertFails(batch.commit());
    assert.equal((await getDoc(doc(db, 'inventory/harvest'))).data().currentStock, 20);
    assert.equal((await getDocs(collection(db, 'sales'))).size, 0);
    assert.equal((await getDocs(collection(db, 'finance_transactions'))).size, 0);
  });
}
for (const [label, options] of Object.entries({
  total: {salePatch: {totalAmount: 1}}, quantity: {salePatch: {quantity: -1}},
  price: {salePatch: {unitPrice: 0}}, infinity: {salePatch: {quantity: Infinity}},
  nan: {salePatch: {quantity: NaN}}, precision: {salePatch: {quantityMilli: 5001}},
  unit: {salePatch: {unit: 'liter'}}, actor: {salePatch: {createdBy: 'field'}},
  status: {salePatch: {status: 'pending'}}, provenance: {salePatch: {batchId: 'invented'}},
  ledgerLink: {ledgerPatch: {saleId: 'missing'}}, income: {financePatch: {amount: 1}},
  financeType: {financePatch: {type: 'expense'}}, financeDate: {financePatch: {date: Timestamp.fromMillis(1)}},
  ledgerSource: {ledgerPatch: {source: 'manual', requestedValue: 5, allowNegative: false}},
  sameBalance: {itemPatch: {currentStock: 20}}, financialActor: {financePatch: {createdBy: 'field'}},
})) test(`phase06 SDK tampering ${label} rejected atomically`, async () => {
  await seedHarvest(); const db = dbFor('admin'), batch = writeBatch(db);
  saleWrites(db, 'admin', 'tampered', 20, options)(batch); await assertFails(batch.commit());
  assert.equal((await getDoc(doc(db, 'inventory/harvest'))).data().currentStock, 20);
});
for (const uid of ['field', 'finance', 'reader', 'inactive']) {
  test(`phase06 ${uid} cannot create integrated sales`, async () => {
    await seedHarvest(); const db = dbFor(uid), batch = writeBatch(db);
    saleWrites(db, uid, 'no-role', 20)(batch); await assertFails(batch.commit());
    if (uid !== 'finance') await assertFails(getDocs(collection(db, 'sales')));
    else await assertSucceeds(getDocs(collection(db, 'sales')));
  });
}
test('phase06 unpaid/non-harvest/unclassified/deleted product and oversell rejected via SDK', async () => {
  const db = dbFor('admin');
  for (const patch of [{isSellable:false}, {productType:'operational'}, {isDeleted:true}]) {
    await seedHarvest(20, patch); const batch = writeBatch(db);
    saleWrites(db, 'admin', 'invalid-product', 20)(batch); await assertFails(batch.commit());
  }
  await seedHarvest(2); const batch = writeBatch(db);
  saleWrites(db, 'admin', 'negative', 2)(batch); await assertFails(batch.commit());
});
test('phase06 completed sales, sale ledger and linked finance are immutable even for admin', async () => {
  await seedHarvest(); await commitSale('permanent'); const db = dbFor('admin');
  for (const path of ['sales/permanent','inventory_transactions/sale_permanent','finance_transactions/sale_permanent']) {
    await assertFails(updateDoc(doc(db,path), {notes: 'edited', updatedBy:'admin', updatedAt:serverTimestamp()}));
    await assertFails(deleteDoc(doc(db,path)));
  }
  await assertFails(updateDoc(doc(db,'finance_transactions/sale_permanent'), {isDeleted:true, updatedBy:'admin',updatedAt:serverTimestamp()}));
});
test('phase06 classification admin only; field cannot mark feed saleable', async () => {
  await seedStock();
  await assertFails(updateDoc(doc(dbFor('field'), 'inventory/feed'), {isSellable:true, productType:'harvest', updatedBy:'field',updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(dbFor('admin'), 'inventory/feed'), {isSellable:true, productType:'harvest', updatedBy:'admin',updatedAt:serverTimestamp()}));
});
function manualCash(id, uid='finance', patch={}) {
  return {id,requestId:id,source:'manual',creationPayload:'payload',version:0,type:'expense',category:'Pakan',
    amount:50000,date:now,description:'',notes:'',paymentMethod:'tunai',moduleType:'lele',isDeleted:false,
    createdBy:uid,updatedBy:uid,createdAt:serverTimestamp(),updatedAt:serverTimestamp(),...patch};
}
async function cashEdit(db, id, editId='edit', patch={amount:60000}) {
  const ref = doc(db,`finance_transactions/${id}`), old = (await getDoc(ref)).data();
  const after = {...old,...patch,version:(old.version??0)+1,lastEditId:editId,updatedBy:'finance',updatedAt:serverTimestamp()};
  const batch=writeBatch(db);
  batch.set(doc(db,`finance_transactions/${id}/edits/${editId}`),{before:old,after,payload:'edit',editedBy:'finance',editedAt:serverTimestamp()});
  batch.set(ref,after); return batch.commit();
}
test('phase06 manual income/expense audit, immutable history and soft delete', async()=>{
  const db=dbFor('finance');
  await assertSucceeds(setDoc(doc(db,'finance_transactions/manual'),manualCash('manual')));
  await assertSucceeds(setDoc(doc(db,'finance_transactions/income'),manualCash('income','finance',{type:'income'})));
  await assertFails(updateDoc(doc(db,'finance_transactions/manual'),{amount:60000,updatedBy:'finance',updatedAt:serverTimestamp()}));
  await assertSucceeds(cashEdit(db,'manual'));
  await assertFails(updateDoc(doc(db,'finance_transactions/manual/edits/edit'),{payload:'forged'}));
  await assertFails(deleteDoc(doc(db,'finance_transactions/manual')));
  await assertSucceeds(cashEdit(db,'manual','delete',{isDeleted:true}));
  await assertFails(cashEdit(db,'manual','restore',{isDeleted:false}));
});
for (const amount of [0,-1,NaN,Infinity,1e13]) test(`phase06 finance invalid amount ${amount}`,async()=>{
  await assertFails(setDoc(doc(dbFor('finance'),'finance_transactions/invalid'),manualCash('invalid','finance',{amount})));
});
test('phase06 manual receipt cannot bypass actor, request or sale pairing',async()=>{
  const db=dbFor('finance');
  for(const patch of [{createdBy:'admin'},{requestId:'different'},{source:'sale',saleId:'none'},{saleId:'none'},{isSampleData:true}]) {
    await assertFails(setDoc(doc(db,'finance_transactions/forged'),manualCash('forged','finance',patch)));
  }
});
const actualFlow=(id='flow',patch={})=>({id,requestId:id,creationPayload:'flow-payload',
  sourceModuleType:'cacing_tanah',destinationModuleType:'tanaman',materialName:'Kascing',
  quantity:3,unit:'kg',flowDate:now,sourceType:'manual',notes:'Aktual',createdBy:'field',createdAt:serverTimestamp(),...patch});
test('phase06 actual flow append-only without stock mutation; legacy remains readable',async()=>{
  const db=dbFor('field'); await seedStock();
  await assertSucceeds(setDoc(doc(db,'circular_flows/flow'),actualFlow()));
  assert.equal((await getDoc(doc(db,'inventory/feed'))).data().currentStock,20);
  assert.equal((await getDocs(collection(db,'inventory_transactions'))).size,0);
  await assertFails(updateDoc(doc(db,'circular_flows/flow'),{quantity:4}));
  await assertFails(deleteDoc(doc(dbFor('admin'),'circular_flows/flow')));
  await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'circular_flows/legacy'),{materialName:'Lama'}));
  await assertSucceeds(getDoc(doc(db,'circular_flows/legacy')));
});
for(const [label,patch] of Object.entries({zero:{quantity:0},negative:{quantity:-1},nan:{quantity:NaN},
  infinite:{quantity:Infinity},module:{sourceModuleType:'invalid'},same:{sourceModuleType:'tanaman'},
  unit:{unit:'invalid'},actor:{createdBy:'admin'},source:{sourceType:'concept'},
  missingBatch:{sourceBatchId:'missing'},wrongLog:{logbookId:'entry'},ledger:{inventoryTransactionId:'missing'}})) {
  test(`phase06 invalid circular ${label} denied`,async()=>{
    await assertFails(setDoc(doc(dbFor('field'),'circular_flows/flow'),actualFlow('flow',patch)));
  });
}
for(const uid of ['finance','reader','inactive']) test(`phase06 flow writer ${uid} denied`,async()=>{
  await assertFails(setDoc(doc(dbFor(uid),'circular_flows/flow'),actualFlow('flow',{createdBy:uid})));
});
test('phase06 sales finance and circular filtered pagination contracts',async()=>{
  const admin=dbFor('admin'); await seedHarvest(200);
  for(let i=0;i<22;i++) await commitSale(`page-${i}`);
  const q=query(collection(admin,'sales'),where('moduleType','==','lele'),where('saleDate','>=',now),orderBy('saleDate','desc'),limit(20));
  const first=await getDocs(q),second=await getDocs(query(q,startAfter(first.docs.at(-1))));
  assert.equal(first.size,20);assert.equal(second.size,2);
  await assertSucceeds(getDocs(query(collection(admin,'finance_transactions'),where('isDeleted','==',false),where('type','==','income'),where('category','==','Penjualan hasil panen'),where('moduleType','==','lele'),orderBy('date','desc'),limit(20))));
  await assertSucceeds(getDocs(query(collection(admin,'circular_flows'),where('sourceModuleType','==','cacing_tanah'),where('destinationModuleType','==','tanaman'),where('materialName','==','Kascing'),orderBy('flowDate','desc'),limit(20))));
});

test('phase06 decimal quantity rounds half Rupiah up, while sample product is rejected',async()=>{
  await seedHarvest();await assertSucceeds(commitSale('round',{quantity:0.125,unitPrice:12}));
  assert.equal((await getDoc(doc(dbFor('admin'),'finance_transactions/sale_round'))).data().amount,2);
  assert.equal((await getDoc(doc(dbFor('admin'),'inventory/harvest'))).data().currentStock,19.875);
  await seedHarvest(20,{isSampleData:true});await assert.rejects(commitSale('sample'));
});
test('phase06 valid flow ledger reference remains append-only without duplicate stock',async()=>{
  await seedStock();
  await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'inventory_transactions/actual'),{
    moduleType:'cacing_tanah',quantity:3,unit:'kg',isReversed:false,createdBy:'field'}));
  await assertSucceeds(setDoc(doc(dbFor('field'),'circular_flows/flow'),actualFlow('flow',{inventoryTransactionId:'actual'})));
  assert.equal((await getDocs(collection(dbFor('field'),'inventory_transactions'))).size,1);
  assert.equal((await getDoc(doc(dbFor('field'),'inventory/feed'))).data().currentStock,20);
});
test('phase06 flow rejects sampled reference, wrong batch and forged actor display name',async()=>{
  await seedBatch();const db=dbFor('field');
  await assertFails(setDoc(doc(db,'circular_flows/flow'),actualFlow('flow',{sourceBatchId:'KOLAM-A'})));
  await assertFails(setDoc(doc(db,'circular_flows/flow'),actualFlow('flow',{createdByName:'Admin'})));
  await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'inventory_transactions/sample'),{
    moduleType:'cacing_tanah',quantity:3,unit:'kg',isReversed:false,createdBy:'sample_seed'}));
  await assertFails(setDoc(doc(db,'circular_flows/flow'),actualFlow('flow',{inventoryTransactionId:'sample'})));
});
test('phase06 finance cannot manufacture orphan audit or initial edit pointer',async()=>{
  const db=dbFor('finance');
  await assertFails(setDoc(doc(db,'finance_transactions/initial'),manualCash('initial','finance',{lastEditId:'forged'})));
  await setDoc(doc(db,'finance_transactions/manual'),manualCash('manual'));
  const old=(await getDoc(doc(db,'finance_transactions/manual'))).data();
  await assertFails(setDoc(doc(db,'finance_transactions/manual/edits/orphan'),{
    before:old,after:old,payload:'forged',editedBy:'finance',editedAt:serverTimestamp()}));
});
