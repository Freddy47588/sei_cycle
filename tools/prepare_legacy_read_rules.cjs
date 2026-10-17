/* Prepare a narrowly scoped release candidate locally. No Firebase calls.
 * Preserve active production rules byte-for-byte except two read-only matches.
 * This avoids bundling hardening that could interrupt old clients using seed masters.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const digest = s => crypto.createHash('sha256').update(s).digest('hex');
const out = path.resolve('build/audit_android/legacy-read-release');
const source = 'build/audit_android/current-rules-source.json';
if (Date.now() - fs.statSync(source).mtimeMs > 5 * 60 * 1000) throw new Error('Refresh active rules read-only before preparing a release');
const active = JSON.parse(fs.readFileSync(source, 'utf8'));
if (!active.name?.startsWith('projects/seicycle-kebun-sei/rulesets/')) throw new Error('Wrong active rules project');
const files = active.source?.files;
if (files?.length !== 1) throw new Error('Expected one reviewed Firestore rules source');
const original = files[0].content;
if (original.includes('match /finance_records/') && original.includes('match /inventory_items/')) {
  const manifestPath = path.join(out, 'manifest.json');
  if (fs.existsSync(manifestPath)) {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    fs.writeFileSync(manifestPath, JSON.stringify({ ...manifest, obsolete: true,
      reason: 'Active Rules now include legacy access; this older candidate must not be deployed.',
      observedActiveSha256: digest(original) }, null, 2));
  }
  console.log(JSON.stringify({ projectId: 'seicycle-kebun-sei', legacyAccessAlreadyPresent: true,
    candidatePrepared: false, productionWrites: 0 }));
  process.exit(0);
}
if (!original.includes('function canManageFinance()') || !original.includes('function canReadOperations()') ||
    original.includes('match /finance_records/') || original.includes('match /inventory_items/')) {
  throw new Error('Active rules differ from the audited baseline; re-audit before preparing a release');
}
const marker = '    match /report_metadata/';
const index = original.indexOf(marker);
if (index < 0) throw new Error('Expected insertion anchor missing');
const addition = `    // Legacy read access only. All existing client mutation rules stay unchanged.
    match /finance_records/{documentId} {
      allow read: if canManageFinance();
      allow write: if false;
    }
    match /inventory_items/{documentId} {
      allow read: if canReadOperations();
      allow write: if false;
    }

`;
const candidate = original.slice(0, index) + addition + original.slice(index);
if (candidate.replace(addition, '') !== original) throw new Error('Unexpected change to existing rules');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'firestore.rules'), candidate);
fs.writeFileSync(path.join(out, 'firebase.json'), JSON.stringify({ firestore: { rules: 'firestore.rules' },
  emulators: { firestore: { host: '127.0.0.1', port: 8097 }, hub: { port: 4401 }, logging: { port: 4501 },
    ui: { enabled: false }, singleProjectMode: true } }, null, 2));
const manifest = { projectId: 'seicycle-kebun-sei', mode: 'local-preparation-only', productionWrites: 0,
  baselineSha256: digest(original), candidateSha256: digest(candidate), existingRulesPreserved: true,
  change: 'Read-only role-constrained access to finance_records and inventory_items; no mutation hardening bundled.',
  approvalRequiredBeforeDeploy: true, createdAtUtc: new Date().toISOString() };
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(JSON.stringify(manifest));
