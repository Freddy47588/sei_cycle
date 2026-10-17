import {readFile} from 'node:fs/promises';
import {test, before, after, beforeEach} from 'node:test';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, getDocs, collection, query, where, updateDoc, deleteDoc, serverTimestamp,writeBatch} from 'firebase/firestore';

let env;
before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host || !host.startsWith('127.0.0.1:')) throw Error('Local emulator required.');
  const [hostname, port] = host.split(':');
  env = await initializeTestEnvironment({projectId:'demo-seicycle-phase07',firestore:{host:hostname,port:Number(port),rules:await readFile(new URL('../../firestore.rules',import.meta.url),'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db=context.firestore();
    for (const [uid, role] of Object.entries({admin:'admin',other:'admin',field:'operator_lapangan',finance:'operator_keuangan',inactive:'admin'}))
      await setDoc(doc(db,'users',uid),{uid,id:uid,role,isActive:uid!=='inactive'});
    for (const status of ['published','draft','archived']) await setDoc(doc(db,'education_contents',status),{status,isDeleted:false});
    for (const [id,data] of Object.entries({own:{userId:'field',targetRole:'operator_lapangan'},private:{userId:'other',targetRole:'operator_lapangan'},admin:{userId:'',targetRole:'admin'},broadcast:{userId:'',targetRole:'all'}}))
      await setDoc(doc(db,'notifications',id),{id,title:'Pengingat',body:'Pesan',isRead:false,isDeleted:false,...data});
    await setDoc(doc(db,'admin_audit/a'),{actorUid:'admin'});
  });
});
const dbFor=uid=>uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
const command=uid=>({actorUid:uid,kind:'preview',targetPath:'batches/b',operation:'delete',reason:'Koreksi input',patch:{},previewId:'',status:'pending',createdAt:serverTimestamp()});
for (const uid of ['admin','field','finance','inactive',null]) test(`Admin request authorization: ${uid}`,async()=>{
  await (uid==='admin'?assertSucceeds:assertFails)(setDoc(doc(dbFor(uid),'admin_requests/r'),command(uid||'')));
});
test('forged actor, ready status and result mutation rejected',async()=>{
  const db=dbFor('admin');
  await assertFails(setDoc(doc(db,'admin_requests/forged'),command('other')));
  await assertFails(setDoc(doc(db,'admin_requests/result'),{...command('admin'),status:'ready'}));
  await assertSucceeds(setDoc(doc(db,'admin_requests/r'),command('admin')));
  await assertFails(updateDoc(doc(db,'admin_requests/r'),{status:'succeeded'}));
  await assertFails(deleteDoc(doc(db,'admin_requests/r')));
  await assertFails(getDoc(doc(dbFor('other'),'admin_requests/r')));
});
test('audit and backup cannot be changed by a client Admin',async()=>{
  const db=dbFor('admin');
  await assertSucceeds(getDoc(doc(db,'admin_audit/a')));
  await assertFails(updateDoc(doc(db,'admin_audit/a'),{actorUid:'other'}));
  await assertFails(deleteDoc(doc(db,'admin_audit/a')));
  await assertFails(setDoc(doc(db,'admin_backups/r/documents/b'),{before:{}}));
});
test('privileged profile edits must pass trusted last-Admin workflow',async()=>{
  await assertFails(updateDoc(doc(dbFor('admin'),'users/admin'),{isActive:false}));
  await assertFails(updateDoc(doc(dbFor('admin'),'users/field'),{role:'admin'}));
  await assertFails(deleteDoc(doc(dbFor('admin'),'users/field')));
});
test('education drafts/archives are Admin-only even through direct SDK',async()=>{
  for (const status of ['published','draft','archived']) {
    await assertSucceeds(getDoc(doc(dbFor('admin'),'education_contents',status)));
    await (status==='published'?assertSucceeds:assertFails)(getDoc(doc(dbFor('field'),'education_contents',status)));
  }
  await assertSucceeds(getDocs(query(collection(dbFor('field'),'education_contents'),where('status','==','published'),where('isDeleted','==',false))));
});
test('UID targeting does not leak through matching role; broadcasts use separate receipts',async()=>{
  const db=dbFor('field');
  await assertSucceeds(getDoc(doc(db,'notifications/own')));
  await assertSucceeds(getDoc(doc(db,'notifications/broadcast')));
  await assertFails(getDoc(doc(db,'notifications/private')));
  await assertFails(getDoc(doc(db,'notifications/admin')));
  await assertSucceeds(setDoc(doc(db,'notification_receipts/field/items/broadcast'),{readAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db,'notification_receipts/other/items/broadcast'),{readAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db,'notifications/broadcast'),{isRead:true}));
  await assertFails(setDoc(doc(db,'notification_receipts/field/items/admin'),{readAt:serverTimestamp()}));
});

test('own read state and role-targeted query remain usable after targeting hardening', async()=>{
  const db=dbFor('field');
  await assertSucceeds(updateDoc(doc(db,'notifications/own'),{isRead:true,readAt:serverTimestamp()}));
  await assertSucceeds(getDocs(query(collection(db,'notifications'),where('userId','==','field'),where('isDeleted','==',false))));
  await assertSucceeds(getDocs(query(collection(db,'notifications'),where('userId','==',''),where('targetRole','in',['operator_lapangan','all']),where('isDeleted','==',false))));
});
test('financial recommendation snapshots cannot leak to field roles',async()=>{
  await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'recommendations/finance'),{type:'finance',title:'Nominal privat'}));
  await assertFails(getDoc(doc(dbFor('field'),'recommendations/finance')));
  await assertSucceeds(getDoc(doc(dbFor('finance'),'recommendations/finance')));
});

test('education edits require exact atomic before/after evidence and protect audit history',async()=>{
  const db=dbFor('admin');const ref=doc(db,'education_contents/draft');
  await assertFails(updateDoc(ref,{title:'Unpaired'}));
  const before=(await getDoc(ref)).data();const after={...before,title:'Diperbarui',updatedBy:'admin',updatedAt:serverTimestamp(),lastEditId:'edit'};
  const batch=writeBatch(db);batch.update(ref,after);
  batch.set(doc(db,'education_edits/edit'),{targetId:'draft',actorUid:'admin',requestId:'edit',operation:'update',before,after,createdAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(db,'education_edits/edit'),{operation:'forged'}));
  await assertFails(deleteDoc(doc(db,'education_edits/edit')));
  await assertFails(deleteDoc(ref));
});

test('removed user cannot recreate a profile from an existing Auth session',async()=>{
  await env.withSecurityRulesDisabled(async c=>{
    await deleteDoc(doc(c.firestore(),'users/field'));
    await setDoc(doc(c.firestore(),'admin_tombstones/users__field'),{targetPath:'users/field'});
  });
  await assertFails(setDoc(doc(dbFor('field'),'users/field'),{uid:'field',id:'field',role:'operator_lapangan',isActive:true}));
});
