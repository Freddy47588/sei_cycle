import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { processRequest } from './management.mjs';
import { processIdentityJob } from './identity.mjs';

const emulator = !!process.env.FIRESTORE_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT;
if (!projectId || (!emulator && process.env.SEICYCLE_ADMIN_WORKER_ENABLED !== 'true')) {
  throw new Error('Set GCLOUD_PROJECT. Production worker also requires SEICYCLE_ADMIN_WORKER_ENABLED=true after deployment review.');
}
if (emulator && !projectId.startsWith('demo-')) throw new Error('Emulator requires demo- project.');
initializeApp({ projectId, ...(emulator ? {} : { credential: applicationDefault() }) });
const db = getFirestore();
const auth = getAuth();
const running = new Set();
const unsubscribe = db.collection('admin_requests').where('status', '==', 'pending').onSnapshot(snapshot => {
  for (const doc of snapshot.docs) {
    if (running.has(doc.id)) continue;
    running.add(doc.id);
    (async () => {
      // Revoked/deleted/disabled Auth identities must not retain privileged access.
      if (!emulator) {
        const identity = await auth.getUser(doc.data().actorUid);
        if (identity.disabled) throw new Error('Akun dinonaktifkan.');
      }
      await processRequest(db, doc.id);
    })().catch(async () => {
      await db.runTransaction(async tx => { const state = await tx.get(doc.ref);
        if (state.data()?.status === 'pending') tx.update(doc.ref, { status: 'failed', error: 'Identitas Admin atau layanan tepercaya belum dapat diverifikasi.' });
      });
    }).finally(() => running.delete(doc.id));
  }
}, () => { process.exitCode = 1; unsubscribe(); });
process.on('SIGINT', () => { unsubscribe(); process.exit(0); });

// Identity changes are a durable outbox because Auth and Firestore cannot share a transaction.
const identities = new Set();
const stopIdentities = db.collection('admin_identity_jobs').where('status', '==', 'pending').onSnapshot(snapshot => {
  for (const job of snapshot.docs) {
    if (identities.has(job.id)) continue;
    identities.add(job.id);
    (async () => {
      if (emulator && !process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Auth emulator required.');
      await processIdentityJob(db, auth, job.id);
    })().catch(async () => {
      await job.ref.update({ status: 'needs_review' });
    }).finally(() => identities.delete(job.id));
  }
});
process.on('SIGINT', () => stopIdentities());
