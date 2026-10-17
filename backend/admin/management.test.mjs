import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { processIdentityJob } from './identity.mjs';
import { planChange, processRequest, categories } from './management.mjs';

const request = (path, operation, patch = {}) => ({targetPath: path, operation, patch, actorUid: 'admin', requestId: 'request', reason: 'Koreksi catatan salah'});
const item = { name: 'Hasil', currentStock: 8, minStock: 2, unit: 'kg', isDeleted: false };
const ledger = { itemId: 'stock', beforeStock: 10, afterStock: 8, quantity: 2, unit: 'kg', type: 'out', source: 'sale', saleId: 'sale' };
const sale = { status: 'paid', quantity: 2, totalAmount: 10000, inventoryTransactionId: 'ledger', financeTransactionId: 'cash' };
const graph = () => ({'users/admin': {role: 'admin', isActive: true}, 'inventory/stock': {...item},
  'sales/sale': {...sale}, 'inventory_transactions/ledger': {...ledger},
  'finance_transactions/cash': {saleId: 'sale', source: 'sale', amount: 10000, isDeleted: false}});

test('unused batch can be permanently deleted, linked batch requires dependency resolution', () => {
  assert.deepEqual(planChange({'batches/b': {status: 'planned'}}, request('batches/b', 'delete')).deletions, ['batches/b']);
  assert.throws(() => planChange({'batches/b': {}, 'logbooks/l': {batchId: 'b'}}, request('batches/b', 'delete')), /dependensi/);
});
test('completed/archived batches can be archived or safely deleted', () => {
  for (const status of ['completed', 'archived']) assert.equal(planChange({'batches/b': {status}}, request('batches/b', 'archive')).writes['batches/b'].status, 'archived');
});
test('sale reversal returns stock and cancels income atomically', () => {
  const plan = planChange(graph(), request('sales/sale', 'reverse'));
  assert.equal(plan.writes['inventory/stock'].currentStock, 10);
  assert.equal(plan.writes['sales/sale'].status, 'cancelled');
  assert.equal(plan.writes['finance_transactions/cash'].isDeleted, true);
  assert.equal(plan.writes['inventory_transactions/ledger'].isReversed, true);
});
test('duplicate reversal and independent sale finance deletion are rejected', () => {
  const records = graph();
  records['sales/sale'].adminReversed = true;
  assert.throws(() => planChange(records, request('sales/sale', 'reverse')), /telah dibalikkan/);
  assert.throws(() => planChange(graph(), request('finance_transactions/cash', 'delete')), /penjualan/);
});
test('missing inventory parent and incomplete financial evidence never invent balances', () => {
  const records = graph(); delete records['inventory/stock'];
  assert.throws(() => planChange(records, request('sales/sale', 'reverse')), /Master stok/);
  const other = graph(); delete other['finance_transactions/cash'];
  assert.throws(() => planChange(other, request('sales/sale', 'reverse')), /tidak lengkap/);
});
test('logbook reversal removes verified production and reverses stock', () => {
  const records = {'logbooks/log': {}, 'inventory/stock': {...item},
    'inventory_transactions/l': {...ledger, source: 'logbook', saleId: '', logbookId: 'log'},
    'production_results/p': {logbookId: 'log', quantity: 2}};
  const plan = planChange(records, request('logbooks/log', 'reverse'));
  assert.equal(plan.writes['logbooks/log'].isDeleted, true);
  assert.equal(plan.writes['production_results/p'].isDeleted, true);
  assert.equal(plan.writes['inventory/stock'].currentStock, 10);
});
test('legacy path collision never deletes the canonical record', () => {
  const records = {'inventory/same': {...item}, 'inventory_items/same': {current_stock: 0}};
  assert.deepEqual(planChange(records, request('inventory_items/same', 'delete')).deletions, ['inventory_items/same']);
});
test('physical master removal requires a verified zero; historical ledger remains', () => {
  assert.throws(() => planChange({'inventory/i': {...item}}, request('inventory/i', 'delete')), /nol/);
  const p = planChange({'inventory/i': {...item, currentStock: 0}, 'inventory_transactions/old': {itemId: 'i'}}, request('inventory/i', 'delete'));
  assert.deepEqual(p.deletions, ['inventory/i']);
});
test('last active Admin cannot be deactivated, including legacy role spellings', () => {
  for (const role of ['admin', 'Admin', ' admin ']) assert.throws(() => planChange({'users/a': {role, isActive: true}}, request('users/a', 'archive')), /terakhir/);
});
test('circular flow correction does not create inventory movement', () => {
  const p = planChange({'circular_flows/f': {quantity: 2, unit: 'kg'}}, request('circular_flows/f', 'update', {quantity: 3}));
  assert.deepEqual(p.affected, ['circular_flows/f']);
});
test('unsafe URL, invented fields, malformed path and sample writes are rejected', () => {
  assert.throws(() => planChange({}, request('education_contents/e', 'create', {title: 'Video', type: 'video', status: 'draft', externalVideoUrl: 'javascript:alert(1)'})), /URL|HTTPS/);
  assert.throws(() => planChange({'inventory/i': item}, request('inventory/i', 'update', {currentStock: 100})), /Field/);
  assert.throws(() => planChange({}, request('users/a/private/x', 'delete')), /Jalur/);
  assert.throws(() => planChange({}, request('farm_modules/a', 'create', {name: 'A', createdBy: 'sample_seed'})), /Field/);
});

const emulator = process.env.FIRESTORE_EMULATOR_HOST;
let app, db;
before(async () => {
  if (!emulator) return;
  if (!/^127\.0\.0\.1:\d+$/.test(emulator)) throw Error('Tests require local emulator.');
  app = initializeApp({projectId: 'demo-seicycle-admin07'}, 'admin07-tests'); db = getFirestore(app);
});
after(async () => { if (app) await deleteApp(app); });
beforeEach(async () => {
  if (!db) return;
  for (const category of [...categories, 'admin_requests', 'admin_audit', 'admin_backups', 'admin_tombstones', 'admin_identity_jobs']) await db.recursiveDelete(db.collection(category));
  await db.doc('users/admin').set({role: 'admin', isActive: true});
});
async function submit(id, command, kind = 'preview', previewId = '') {
  await db.doc(`admin_requests/${id}`).set({...command, kind, previewId, status: 'pending', createdAt: Timestamp.now()});
  await processRequest(db, id); return (await db.doc(`admin_requests/${id}`).get()).data();
}
test('emulator: preview, permanent delete, protected backup and idempotent retry', {skip: !emulator}, async () => {
  await db.doc('batches/b').set({status: 'planned'});
  const command = request('batches/b', 'delete');
  assert.equal((await submit('preview', command)).status, 'ready');
  assert.equal((await submit('execute', command, 'execute', 'preview')).status, 'succeeded');
  assert.equal((await db.doc('batches/b').get()).exists, false);
  assert.equal((await db.doc('admin_backups/execute/documents/batches__b').get()).exists, true);
  await processRequest(db, 'execute');
  assert.equal((await db.collection('admin_audit').get()).size, 1);
});
test('emulator: stale preview rejects concurrent dependencies without partial writes', {skip: !emulator}, async () => {
  await db.doc('batches/b').set({status: 'planned'});
  const command = request('batches/b', 'delete'); await submit('p', command);
  await db.doc('logbooks/new').set({batchId: 'b'});
  assert.equal((await submit('e', command, 'execute', 'p')).status, 'failed');
  assert.equal((await db.doc('batches/b').get()).exists, true);
  assert.equal((await db.doc('admin_audit/e_failed').get()).data().result, 'failed');
});
test('emulator: forged, inactive and non-admin actor denied by processor', {skip: !emulator}, async () => {
  await db.doc('batches/b').set({});
  for (const [uid, profile] of Object.entries({field: {role:'operator_lapangan'}, inactive: {role:'admin',isActive:false}})) {
    await db.doc(`users/${uid}`).set(profile);
    assert.equal((await submit(uid, {...request('batches/b','delete'), actorUid: uid})).status, 'failed');
  }
  assert.equal((await submit('anonymous', {...request('batches/b','delete'), actorUid: ''})).status, 'failed');
});
test('emulator: sale cancellation retry changes stock and finance exactly once', {skip: !emulator}, async () => {
  for (const [path, d] of Object.entries(graph())) await db.doc(path).set(d);
  const command = request('sales/sale', 'reverse'); await submit('p', command);
  assert.equal((await submit('e', command, 'execute', 'p')).status, 'succeeded');
  await processRequest(db, 'e');
  assert.equal((await db.doc('inventory/stock').get()).data().currentStock, 10);
  assert.equal((await db.doc('finance_transactions/cash').get()).data().isDeleted, true);
});

test('linked production cannot be deleted independently and missing Logbook stock effects are rejected', () => {
  assert.throws(() => planChange({'production_results/p': {logbookId:'l'}}, request('production_results/p','delete')), /Logbook/);
  assert.throws(() => planChange({'logbooks/l': {details:{dedak_padi_kg:2}}}, request('logbooks/l','delete')), /tidak lengkap/);
});
test('terminal inverse ledger pair can be removed with zero balance and exact backup manifest', () => {
  const records = {'inventory/i': {currentStock:0,lastTransactionId:'inverse'},
    'inventory_transactions/original': {itemId:'i',beforeStock:0,afterStock:2,adminReversed:true},
    'inventory_transactions/inverse': {id:'inverse',itemId:'i',source:'admin_reversal',reversalOf:'inventory_transactions/original',beforeStock:2,afterStock:0}};
  const plan = planChange(records,request('inventory_transactions/original','delete'));
  assert.deepEqual(plan.deletions.sort(),['inventory_transactions/inverse','inventory_transactions/original']);
  assert.equal(plan.writes['inventory/i'].currentStock,0);
});

test('emulator: identity outbox creation keeps the profile inactive and rejects existing UID adoption', {skip: !emulator}, async () => {
  const command = request('users/newuser','create',{name:'Tim',email:'fixture@example.test',role:'operator_lapangan',isActive:true});
  await submit('p',command);
  assert.equal((await submit('e',command,'execute','p')).status,'identity_pending');
  assert.equal((await db.doc('users/newuser').get()).data().isActive,false);
  const calls=[];
  await processIdentityJob(db,{createUser: async input=>{calls.push(input);throw Object.assign(Error('exists'),{code:'auth/uid-already-exists'});}},'e');
  assert.equal(calls.length,1);
  assert.equal((await db.doc('admin_requests/e').get()).data().status,'needs_review');
  assert.equal((await db.doc('users/newuser').get()).data().identityPending,true);
  await processIdentityJob(db,{createUser:async()=>{throw Error('must not retry');}},'e');
});
test('emulator: identity deletion is idempotent and records its separate audit result', {skip: !emulator}, async () => {
  await db.doc('users/retired').set({role:'operator_lapangan',isActive:false});
  const command=request('users/retired','deleteIdentity');await submit('p',command);
  assert.equal((await submit('e',command,'execute','p')).status,'identity_pending');
  let calls=0;
  await processIdentityJob(db,{deleteUser:async()=>{calls++;throw Object.assign(Error('gone'),{code:'auth/user-not-found'});}},'e');
  await processIdentityJob(db,{deleteUser:async()=>calls++},'e');
  assert.equal(calls,1);assert.equal((await db.doc('admin_requests/e').get()).data().status,'succeeded');
  assert.equal((await db.doc('admin_audit/e_identity').get()).data().result,'succeeded');
});

test('Auth emulator: provision and remove identity without replacing a Firebase UID', {skip: !emulator || !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const auth=getAuth(app);const uid='phase07-identity-fixture';
  try {await auth.deleteUser(uid);} catch(e) {if(e.code!=='auth/user-not-found')throw e;}
  const command=request(`users/${uid}`,'create',{name:'Fixture',email:'identity-fixture@example.test',role:'operator_lapangan'});
  await submit('p',command);await submit('e',command,'execute','p');
  await processIdentityJob(db,auth,'e');
  assert.equal((await auth.getUser(uid)).uid,uid);
  assert.equal((await db.doc(`users/${uid}`).get()).data().isActive,false);
  const reset=await auth.generatePasswordResetLink('identity-fixture@example.test');
  assert.ok(reset.includes('oobCode='));
  const remove=request(`users/${uid}`,'deleteIdentity');await submit('p2',remove);await submit('e2',remove,'execute','p2');
  await processIdentityJob(db,auth,'e2');
  await assert.rejects(auth.getUser(uid),e=>e.code==='auth/user-not-found');
});

for (const [category, old, patch] of [
  ['farm_modules',{name:'Lele'},{description:'Diperbaiki'}],
  ['batches',{moduleType:'lele',status:'planned',name:'Batch'},{name:'Batch benar'}],
  ['logbooks',{notes:'Awal'},{notes:'Koreksi'}],
  ['inventory',{...item,currentStock:0},{minStock:4}],
  ['inventory_items',{current_stock:0,name:'Legacy'},{name:'Legacy benar'}],
  ['production_results',{moduleType:'lele',productName:'Hasil',quantity:2,unit:'kg',harvestDate:Timestamp.now()},{quantity:3}],
  ['schedules',{title:'Jadwal',status:'done'},{status:'pending'}],
  ['finance_transactions',{type:'income',amount:100,source:'manual',isDeleted:false},{amount:200}],
  ['finance_records',{type:'expense',amount:100},{amount:200}],
  ['circular_flows',{materialName:'Bahan',quantity:2},{quantity:3}],
  ['education_contents',{title:'Materi',type:'artikel',content:'Isi',status:'draft'},{status:'archived'}],
  ['notifications',{title:'Alert',body:'Pesan',userId:'',targetRole:'all'},{title:'Alert benar'}],
  ['recommendations',{title:'Saran',description:'Alasan',priority:'low'},{priority:'medium'}],
  ['report_metadata',{name:'Laporan'},{name:'Laporan benar'}],
]) test(`reviewed metadata CRUD plan for ${category}`,()=>{
  const path=`${category}/record`;
  const plan=planChange({[path]:old},request(path,'update',patch));
  for(const [key,value] of Object.entries(patch))assert.equal(plan.writes[path][key],value);
  assert.deepEqual(planChange({[path]:{...old,isDeleted:true}},request(path,'delete')).deletions,[path]);
});
