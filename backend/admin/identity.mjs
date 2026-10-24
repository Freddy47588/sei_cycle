import { FieldValue } from 'firebase-admin/firestore';

/** Durable Auth outbox. Profiles stay inactive until identity creation is verified. */
export async function processIdentityJob(db, auth, jobId) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(jobId)) throw Error('Invalid job ID');
  const ref = db.doc(`admin_identity_jobs/${jobId}`);
  const data = await db.runTransaction(async tx => {
    const job = await tx.get(ref);
    const request = await tx.get(db.doc(`admin_requests/${jobId}`));
    if (job.data()?.status !== 'pending' || request.data()?.status !== 'identity_pending') return null;
    tx.update(ref, { status: 'processing', startedAt: FieldValue.serverTimestamp() });
    return job.data();
  });
  if (!data) return;
  let result = 'succeeded';
  try {
    if (data.action === 'delete') {
      try { await auth.deleteUser(data.uid); } catch (e) { if (e.code !== 'auth/user-not-found') throw e; }
    } else if (data.action === 'create') {
      // Existing identities are never adopted by matching an email or UID.
      await auth.createUser({ uid: data.uid, email: data.email, displayName: data.name, disabled: false });
    } else throw Error('Unsupported identity operation');
  } catch { result = 'needs_review'; }
  await db.runTransaction(async tx => {
    const profile = await tx.get(db.doc(`users/${data.uid}`));
    const message = result === 'needs_review' ? 'Identitas belum terverifikasi; periksa status Auth dan profil sebelum mencoba ulang.' : '';
    tx.update(ref, { status: result, error: message, completedAt: FieldValue.serverTimestamp() });
    tx.update(db.doc(`admin_requests/${jobId}`), { status: result, error: message });
    if (result === 'succeeded' && data.action === 'create' && profile.exists) {
      tx.update(profile.ref, { identityPending: false });
    }
    tx.create(db.doc(`admin_audit/${jobId}_identity`), { actorUid: data.actorUid,
      targetPath: `users/${data.uid}`, operation: `auth_${data.action}`, requestId: jobId,
      result, createdAt: FieldValue.serverTimestamp() });
  });
}
