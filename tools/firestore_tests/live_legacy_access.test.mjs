import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { collection, doc, getDocs, setDoc, updateDoc, deleteDoc, query, orderBy, limit, setLogLevel } from 'firebase/firestore';
setLogLevel('silent');
let env;
before(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '').split(':');
  if (host !== '127.0.0.1' || port !== '8097') throw new Error('Dedicated loopback demo emulator required');
  env = await initializeTestEnvironment({ projectId: 'demo-seicycle-legacy-read', firestore: { host, port: Number(port),
    rules: await readFile(new URL('../../build/audit_android/legacy-read-release/firestore.rules', import.meta.url), 'utf8') } });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async c => {
    const db = c.firestore();
    for (const [uid, role] of Object.entries({admin:'admin',finance:'operator_keuangan',field:'operator_lapangan',reader:'mitra',inactive:'admin'})) {
      await setDoc(doc(db,'users',uid),{id:uid,uid,role,isActive:uid!=='inactive'});
    }
    await setDoc(doc(db,'finance_records/legacy'),{type:'income',amount:10});
    await setDoc(doc(db,'inventory_items/legacy'),{current_stock:3});
  });
});
for (const uid of ['admin','finance','field','reader','inactive']) {
  test(`minimal legacy read release respects ${uid} role and forbids every legacy write`, async () => {
    const db = env.authenticatedContext(uid).firestore();
    await (['admin','finance'].includes(uid) ? assertSucceeds : assertFails)(getDocs(query(collection(db,'finance_records'),orderBy('__name__'),limit(100))));
    await (uid!=='inactive' ? assertSucceeds : assertFails)(getDocs(query(collection(db,'inventory_items'),orderBy('__name__'),limit(100))));
    for (const name of ['finance_records','inventory_items']) {
      await assertFails(setDoc(doc(db,name,'new'),{value:1}));
      await assertFails(updateDoc(doc(db,name,'legacy'),{value:2}));
      await assertFails(deleteDoc(doc(db,name,'legacy')));
    }
  });
}
