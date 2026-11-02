import {readFile} from 'node:fs/promises';
import {test, before, after, beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, getDocs, collection, query, where, runTransaction, serverTimestamp, Timestamp} from 'firebase/firestore';

let env;
before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!/^127\.0\.0\.1:\d+$/.test(host || '')) throw Error('Loopback emulator required');
  const [hostname, port] = host.split(':');
  env = await initializeTestEnvironment({projectId:'demo-seicycle-education08',firestore:{host:hostname,port:Number(port),rules:await readFile(new URL('../../firestore.rules',import.meta.url),'utf8')}});
});
after(async () => {await env?.cleanup();});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    for (const [uid, role] of Object.entries({admin:'admin',field:'operator_lapangan'})) {
      await setDoc(doc(context.firestore(),'users',uid),{id:uid,uid,role,isActive:true});
    }
  });
});
const dbFor=uid=>env.authenticatedContext(uid).firestore();
let serial=0;
async function write(db,id,patch,{create=false,actor='admin'}={}) {
  const editId=`education08-${++serial}`;
  await runTransaction(db,async tx=>{
    const ref=doc(db,'education_contents',id);
    const snapshot=await tx.get(ref);
    const before=snapshot.exists()?snapshot.data():null;
    const after={...before,...patch,updatedBy:actor,updatedAt:serverTimestamp(),lastEditId:editId};
    tx.set(ref,after);
    tx.set(doc(db,'education_edits',editId),{targetId:id,actorUid:actor,requestId:editId,
      operation:create?'create':patch.isDeleted?'softDelete':'update',before,after,createdAt:serverTimestamp()});
  });
}
const payload=(id,type)=>({id,title:'Materi',type,status:'draft',moduleType:'lele',category:'Panduan',tags:['Budidaya'],summary:'Isi ringkas',content:'Isi atau langkah lengkap',externalVideoUrl:'https://example.test/tutorial',thumbnailUrl:'',duration:'05:00',steps:['Langkah satu','Langkah dua'],toolsNeeded:['Sarung tangan'],safetyNotes:'Gunakan alat aman',authorId:'admin',createdBy:'admin',createdAt:serverTimestamp(),isDeleted:false});
for (const type of ['artikel','video','sop']) test(`real SDK ${type} service-shaped create/edit/publish/archive/delete succeeds atomically`,async()=>{
  const db=dbFor('admin');const id=`content-${type}`;
  await assertSucceeds(write(db,id,payload(id,type),{create:true}));
  const version=(await getDoc(doc(db,'education_contents',id))).data();
  assert.ok(version.updatedAt instanceof Timestamp);
  await assertFails(getDoc(doc(dbFor('field'),'education_contents',id)));
  await assertSucceeds(write(db,id,{title:'Materi diperbarui'}));
  await assertSucceeds(write(db,id,{status:'published'}));
  await assertSucceeds(getDoc(doc(dbFor('field'),'education_contents',id)));
  await assertSucceeds(write(db,id,{status:'archived'}));
  await assertFails(getDoc(doc(dbFor('field'),'education_contents',id)));
  await assertSucceeds(write(db,id,{isDeleted:true}));
  assert.equal((await getDoc(doc(db,'education_contents',id))).data().isDeleted,true);
  assert.equal((await getDocs(query(collection(db,'education_contents'),where('isDeleted','==',false)))).size,0);
  assert.equal((await getDocs(collection(db,'education_edits'))).size,5);
});
test('sample-origin education can be corrected and soft-deleted with exact audit without rewriting provenance',async()=>{
  await env.withSecurityRulesDisabled(context=>setDoc(doc(context.firestore(),'education_contents/legacy'),{...payload('legacy','artikel'),createdBy:'sample_seed',isSampleData:true,sampleVersion:'v2',createdAt:Timestamp.now(),updatedAt:Timestamp.now()}));
  const db=dbFor('admin');
  await assertSucceeds(write(db,'legacy',{title:'Koreksi konten'}));
  await assertSucceeds(write(db,'legacy',{isDeleted:true}));
  const current=(await getDoc(doc(db,'education_contents/legacy'))).data();
  assert.equal(current.createdBy,'sample_seed');assert.equal(current.isSampleData,true);
});
test('field role cannot create service-shaped education or its audit',async()=>{
  const db=dbFor('field');
  await assertFails(write(db,'unauthorized',{...payload('unauthorized','artikel'),authorId:'field',createdBy:'field'},{create:true,actor:'field'}));
  await env.withSecurityRulesDisabled(async context=>{
    assert.equal((await getDocs(collection(context.firestore(),'education_contents'))).size,0);
    assert.equal((await getDocs(collection(context.firestore(),'education_edits'))).size,0);
  });
});
