/* Restore rehearsal ONLY in a loopback Firestore Emulator and fixed demo project.
 * Restores typed document fields, then reads every document back for comparison.
 * Does not restore Auth users, original createTime/updateTime, rules or indexes.
 * Never use this as a production restore/cleanup executor.
 */
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { decodeFields } = require('./firestore_readonly_audit.cjs');

async function main() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!/^127\.0\.0\.1:\d{2,5}$/.test(host || '')) throw new Error('A loopback Firestore Emulator is required');
  const snapshot = JSON.parse(fs.readFileSync('build/audit_android/production-snapshot.json', 'utf8'));
  if (!snapshot.allCollectionsEnumerated || !snapshot.documents.length) throw new Error('Complete typed snapshot required');
  const base = `http://${host}/v1/projects/demo-seicycle-audit-restore/databases/(default)/documents`;
  const headers = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };
  for (const d of snapshot.documents) {
    if (!d.rawFields || !/^(?:[^/]+\/[^/]+)(?:\/[^/]+\/[^/]+)*$/.test(d.path)) throw new Error('Invalid backup document');
    assert.deepStrictEqual(decodeFields(d.rawFields), d.data);
  }
  for (let offset = 0; offset < snapshot.documents.length; offset += 200) {
    const r = await fetch(base + ':commit', { method: 'POST', headers, body: JSON.stringify({ writes: snapshot.documents.slice(offset, offset + 200).map(d => ({ update: { name: base.split('/v1/')[1] + '/' + d.path, fields: d.rawFields } })) }) });
    if (!r.ok) throw new Error(`Emulator restore failed: HTTP ${r.status}`);
  }
  for (let offset = 0; offset < snapshot.documents.length; offset += 6) {
    await Promise.all(snapshot.documents.slice(offset, offset + 6).map(async d => {
      const r = await fetch(base + '/' + d.path, { headers });
      if (!r.ok) throw new Error('Emulator read-back failed');
      const restored = await r.json();
      assert.deepStrictEqual(restored.fields || {}, d.rawFields);
    }));
  }
  const result = { mode: 'emulator-only-restore-rehearsal', projectId: 'demo-seicycle-audit-restore', documentsRestoredAndCompared: snapshot.documents.length, typedFieldsMatch: true, authenticationModified: false, productionWrites: 0, metadataTimestampsRestored: false };
  fs.writeFileSync('build/audit_android/restore-rehearsal.json', JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}
if (require.main === module) main().catch(error => {
  // Assertion details can contain personal fields, so do not print the error object.
  console.error(`Emulator restore rehearsal failed (${error.constructor.name}).`);
  process.exitCode = 1;
});
