/* Targeted READ-ONLY refresh; credentials stay in memory, raw output in build/.
 * Reuses the prior inventory, refreshing only the operational root collections.
 * Does not claim a new globally atomic or complete nested database snapshot.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { decodeFields } = require('./firestore_readonly_audit.cjs');
const PROJECT = 'seicycle-kebun-sei';
const COLLECTIONS = ['inventory', 'inventory_items', 'inventory_transactions', 'logbooks',
  'production_results', 'batches', 'farm_modules', 'finance_transactions',
  'finance_records', 'sales', 'notifications', 'schedules'];
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const normalize = s => s.replace(/\r\n/g, '\n').trim();
function normalizeIndexes(indexes) {
  return indexes.map(i => JSON.stringify({ collectionGroup: i.collectionGroup || i.name.split('/collectionGroups/')[1].split('/')[0],
    queryScope: i.queryScope, fields: i.fields.filter(f => f.fieldPath !== '__name__') })) .sort();
}
async function main() {
  if (process.argv.slice(2).join(' ') !== `--project ${PROJECT}`) throw new Error('Explicit project required');
  const out = path.resolve('build/stabilization');
  fs.mkdirSync(out, { recursive: true });
  const baseline = JSON.parse(fs.readFileSync('build/audit_android/production-snapshot.json', 'utf8'));
  if (baseline.projectId !== PROJECT || !baseline.allCollectionsEnumerated) throw new Error('Verified baseline required');
  const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));
  const account = auth.getProjectDefaultAccount(process.cwd());
  if (!account) throw new Error('Authenticated CLI account required');
  const tokens = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
  const headers = { Authorization: `Bearer ${tokens.access_token}`, 'Content-Type': 'application/json' };
  let requests = 0;
  async function read(url, body) {
    if (++requests > 150) throw new Error('Read budget exceeded');
    const r = await fetch(url, { headers, method: body ? 'POST' : 'GET',
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30000) });
    if (!r.ok) throw new Error(`Read failed HTTP ${r.status} at request ${requests}`);
    return r.json();
  }
  const db = `projects/${PROJECT}/databases/(default)`;
  const metadata = await read(`https://firestore.googleapis.com/v1/${db}`);
  if (metadata.name !== db || metadata.locationId !== 'asia-southeast2' || metadata.type !== 'FIRESTORE_NATIVE') throw new Error('Unexpected database');
  const permissions = (await read(`https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT}:testIamPermissions`, {
    permissions: ['datastore.entities.get', 'datastore.entities.list', 'datastore.databases.getMetadata'],
  })).permissions || [];
  if (permissions.length !== 3) throw new Error('Required read permissions missing');
  const release = await read(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);
  const rules = await read(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  const rulesSource = rules.source.files.find(f => f.name.endsWith('.rules'))?.content || rules.source.files[0].content;
  const indexes = [];
  let indexPage;
  do {
    const r = await read(`https://firestore.googleapis.com/v1/${db}/collectionGroups/-/indexes${indexPage ? '?pageToken=' + encodeURIComponent(indexPage) : ''}`);
    indexes.push(...(r.indexes || [])); indexPage = r.nextPageToken;
  } while (indexPage);
  const documents = [];
  const counts = {};
  const changes = { added: 0, updated: 0, removed: 0, unchanged: 0 };
  for (const collection of COLLECTIONS) {
    let page;
    const docs = [];
    do {
      const r = await read(`https://firestore.googleapis.com/v1/${db}/documents/${collection}?pageSize=100${page ? '&pageToken=' + encodeURIComponent(page) : ''}`);
      docs.push(...(r.documents || [])); page = r.nextPageToken;
      if (docs.length > 500) throw new Error('Collection budget exceeded; incomplete refresh');
    } while (page);
    const old = new Map(baseline.documents.filter(d => d.path.startsWith(collection + '/') && d.path.split('/').length === 2).map(d => [d.path, d]));
    for (const d of docs) {
      const relative = d.name.split('/documents/')[1];
      const previous = old.get(relative);
      changes[!previous ? 'added' : previous.updateTime === d.updateTime ? 'unchanged' : 'updated']++;
      old.delete(relative);
      documents.push({ path: relative, data: decodeFields(d.fields || {}), rawFields: d.fields || {}, createTime: d.createTime, updateTime: d.updateTime });
    }
    changes.removed += old.size;
    counts[collection] = { before: baseline.documents.filter(d => d.path.split('/').length === 2 && d.path.startsWith(collection + '/')).length, after: docs.length };
  }
  const capturedAtUtc = new Date().toISOString();
  fs.writeFileSync(path.join(out, 'reconciliation-snapshot.json'), JSON.stringify({
    projectId: PROJECT, databaseId: '(default)', capturedAtUtc, mode: 'read-only-targeted-roots',
    completeCollections: COLLECTIONS, allCollectionsEnumerated: false, documents,
  }, null, 2));
  fs.writeFileSync(path.join(out, 'active-rules.json'), JSON.stringify(rules, null, 2));
  fs.writeFileSync(path.join(out, 'active-indexes.json'), JSON.stringify(indexes, null, 2));
  const evidence = { projectId: PROJECT, databaseId: '(default)', location: metadata.locationId,
    capturedAtUtc, authenticatedAccountVerified: !!account.user?.email, requiredReadPermissionsConfirmed: true,
    readRequests: requests, counts, changes, activeRulesSha256: hash(normalize(rulesSource)),
    localRulesSha256: hash(normalize(fs.readFileSync('firestore.rules', 'utf8'))),
    activeRulesMatchRepository: normalize(rulesSource) === normalize(fs.readFileSync('firestore.rules', 'utf8')),
    activeIndexCount: indexes.length, allIndexesReady: indexes.every(i => i.state === 'READY'),
    indexesMatchRepository: JSON.stringify(normalizeIndexes(indexes)) === JSON.stringify(normalizeIndexes(JSON.parse(fs.readFileSync('firestore.indexes.json')).indexes)),
    productionWrites: 0, nestedBackupRefreshed: false, atomicSnapshot: false };
  fs.writeFileSync(path.join(out, 'refresh-evidence.json'), JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence));
}
module.exports = { COLLECTIONS, normalizeIndexes };
if (require.main === module) main().catch(error => {
  const safe = /^(Read failed HTTP \d+ at request \d+|Read budget exceeded|Explicit project required|Verified baseline required|Authenticated CLI account required|Unexpected database|Required read permissions missing|Collection budget exceeded; incomplete refresh)$/;
  console.error(`Targeted read-only refresh failed (${safe.test(error.message) ? error.message : error.constructor.name}); no writes performed.`);
  process.exitCode = 1;
});
