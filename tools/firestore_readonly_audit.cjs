/* Read-only Firestore inventory. Uses the existing Firebase CLI session in memory.
 * No document write, delete, deployment or Authentication API is implemented.
 * Raw typed fields and personal data stay under the ignored build directory.
 * Requires Node 20+ and an installed, authenticated firebase-tools CLI.
 */
const fs = require('node:fs');
const path = require('node:path');

function decode(value) {
  if ('nullValue' in value) return null;
  if ('booleanValue' in value) return value.booleanValue;
  // Preserve large integers as strings instead of silently losing precision.
  if ('integerValue' in value) {
    const n = Number(value.integerValue);
    return Number.isSafeInteger(n) ? n : value.integerValue;
  }
  if ('doubleValue' in value) return value.doubleValue;
  if ('mapValue' in value) return decodeFields(value.mapValue.fields || {});
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decode);
  return value.stringValue ?? value.timestampValue ?? value.referenceValue ?? value.geoPointValue ?? value.bytesValue;
}
function decodeFields(fields) {
  return Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, decode(v)]));
}

async function main() {
  const args = process.argv.slice(2);
  if (![2, 3].includes(args.length) || args[0] !== '--project' || args[1] !== 'seicycle-kebun-sei' ||
      (args.length === 3 && args[2] !== '--evidence-only')) {
    throw new Error('Usage: node tools/firestore_readonly_audit.cjs --project seicycle-kebun-sei [--evidence-only]');
  }
  const project = args[1];
  const out = path.resolve('build/audit_android');
  fs.mkdirSync(out, { recursive: true });
  let cli;
  try { cli = path.dirname(require.resolve('firebase-tools/package.json')); }
  catch {
    if (!process.env.APPDATA) throw new Error('firebase-tools must be installed');
    cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools');
  }
  const auth = require(path.join(cli, 'lib/auth.js'));
  const account = auth.getProjectDefaultAccount(process.cwd());
  if (!account) throw new Error('No authenticated Firebase CLI session');
  const tokens = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
  const headers = { Authorization: 'Bearer ' + tokens.access_token, 'Content-Type': 'application/json' };
  const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
  let requests = 0;
  async function request(url, body) {
    if (++requests > 2000) throw new Error('Read-only audit request budget exceeded');
    const r = await fetch(url, { headers, method: body ? 'POST' : 'GET', ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(45000) });
    if (!r.ok) throw new Error(`Read-only administrative request failed: HTTP ${r.status}`);
    return r.json();
  }
  if (args[2] === '--evidence-only') {
    const database = await request(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`);
    const evidence = { projectId: project, database: database.name, locationId: database.locationId,
      type: database.type, capturedAtUtc: new Date().toISOString(), mode: 'read-only', writes: 0 };
    try {
      const permissions = await request(`https://cloudresourcemanager.googleapis.com/v1/projects/${project}:testIamPermissions`, {
        permissions: ['datastore.entities.get', 'datastore.entities.list', 'datastore.databases.getMetadata',
          'logging.logEntries.list', 'logging.privateLogEntries.list'],
      });
      evidence.confirmedReadPermissions = permissions.permissions || [];
    } catch (error) { evidence.permissionInspection = error.message; }
    try {
      const logs = await request('https://logging.googleapis.com/v2/entries:list', {
        resourceNames: [`projects/${project}`], pageSize: 100, orderBy: 'timestamp desc',
        filter: 'resource.type="firestore_database" AND timestamp>="2026-10-14T17:00:00Z" AND timestamp<="2026-10-16T23:59:59Z" AND (protoPayload.methodName="google.firestore.v1.Firestore.DeleteDocument" OR protoPayload.methodName="google.firestore.v1.Firestore.Commit" OR protoPayload.methodName="google.firestore.v1.Firestore.BatchWrite")',
      });
      evidence.auditLogEntriesReturned = (logs.entries || []).length;
      evidence.auditLogHasMore = !!logs.nextPageToken;
      evidence.auditLogMethods = [...new Set((logs.entries || []).map(e => e.protoPayload?.methodName).filter(Boolean))];
      evidence.deletionEvidenceLimitation = 'An empty read result does not prove no deletion occurred; Data Access logs may not have been enabled or retained. No deleted content was reconstructed.';
    } catch (error) { evidence.auditLogInspection = error.message; }
    fs.writeFileSync(path.join(out, 'admin-evidence.json'), JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence));
    return;
  }
  async function collectionIds(parent) {
    let pageToken;
    const ids = [];
    do {
      const r = await request(parent + ':listCollectionIds', { pageSize: 100, ...(pageToken ? { pageToken } : {}) });
      ids.push(...(r.collectionIds || [])); pageToken = r.nextPageToken;
    } while (pageToken);
    return ids;
  }
  const known = ['users', 'farm_modules', 'logbooks', 'inventory', 'inventory_transactions', 'production_results', 'circular_flows', 'schedules', 'notifications', 'education_contents', 'finance_transactions', 'recommendations', 'batches', 'sales', 'report_metadata'];
  const roots = [...new Set([...known, ...await collectionIds(base)])].sort();
  const snapshot = { projectId: project, capturedAtUtc: new Date().toISOString(), completeCollections: [], allCollectionsEnumerated: false, documents: [], missingParents: [] };
  let queue = roots.map(c => ({ url: base + '/' + encodeURIComponent(c), root: c }));
  while (queue.length) {
    const next = [];
    for (let offset = 0; offset < queue.length; offset += 6) {
      await Promise.all(queue.slice(offset, offset + 6).map(async entry => {
        let pageToken;
        const documents = [];
        do {
          const url = new URL(entry.url);
          url.searchParams.set('pageSize', '300'); url.searchParams.set('showMissing', 'true');
          if (pageToken) url.searchParams.set('pageToken', pageToken);
          const r = await request(url);
          documents.push(...(r.documents || [])); pageToken = r.nextPageToken;
          if (documents.length > 1000 || snapshot.documents.length + documents.length > 5000) throw new Error('Read-only audit document budget exceeded; no complete manifest produced');
        } while (pageToken);
        for (const d of documents) {
          const relative = d.name.split('/documents/')[1];
          if (d.createTime) snapshot.documents.push({ path: relative, data: decodeFields(d.fields || {}), updateTime: d.updateTime, createTime: d.createTime, rawFields: d.fields || {} });
          else snapshot.missingParents.push(relative);
        }
        // Enumerate descendants of missing parents as well as existing documents.
        for (let i = 0; i < documents.length; i += 6) {
          await Promise.all(documents.slice(i, i + 6).map(async d => {
            for (const id of await collectionIds('https://firestore.googleapis.com/v1/' + d.name)) {
              next.push({ url: 'https://firestore.googleapis.com/v1/' + d.name + '/' + encodeURIComponent(id) });
            }
          }));
        }
        if (entry.root) snapshot.completeCollections.push(entry.root);
      }));
    }
    queue = next;
  }
  snapshot.documents.sort((a, b) => a.path.localeCompare(b.path));
  snapshot.completeCollections.sort(); snapshot.allCollectionsEnumerated = true;
  fs.writeFileSync(path.join(out, 'production-snapshot.json'), JSON.stringify(snapshot, null, 2));
  const indexes = await request(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/-/indexes`);
  fs.writeFileSync(path.join(out, 'active-indexes.json'), JSON.stringify(indexes, null, 2));
  const release = await request(`https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore`);
  const rules = await request('https://firebaserules.googleapis.com/v1/' + release.rulesetName);
  fs.writeFileSync(path.join(out, 'active-rules-source.json'), JSON.stringify(rules, null, 2));
  console.log(JSON.stringify({ projectId: project, mode: 'read-only', documents: snapshot.documents.length, roots: roots.length, allCollectionsEnumerated: true, indexes: (indexes.indexes || []).length, output: 'build/audit_android', writes: 0 }));
}
module.exports = { decode, decodeFields };
if (require.main === module) main().catch(error => {
  // Deliberately do not print SDK error objects, HTTP bodies or credentials.
  console.error(error.message.startsWith('Read-only') || error.message.startsWith('Usage:') ? error.message : `Read-only audit failed (${error.constructor.name}); no cleanup is authorized.`);
  process.exitCode = 1;
});
