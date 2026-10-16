"""Read-only offline audit of a reviewed JSON snapshot; never contacts/deletes Firestore.

Input: {projectId, completeCollections: [names], documents: [{path, data, updateTime}]}.
Use an administrative export adapter to decode Firestore values to plain JSON.
This is NOT a decoder for the binary managed Firestore export format.
"""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

COLLECTIONS = {
    'users', 'farm_modules', 'logbooks', 'inventory', 'inventory_transactions',
    'production_results', 'circular_flows', 'schedules', 'notifications',
    'education_contents', 'finance_transactions', 'recommendations', 'batches', 'sales',
}
PROTECTED = {'users', 'farm_modules', 'inventory', 'inventory_transactions',
             'production_results', 'finance_transactions', 'sales', 'logbooks'}


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)


def audit(snapshot, project_id, approved=()):
    if not project_id or snapshot.get('projectId') != project_id:
        raise ValueError('Explicit project ID must match snapshot projectId.')
    docs = snapshot.get('documents', [])
    paths = [doc['path'] for doc in docs]
    if len(paths) != len(set(paths)):
        raise ValueError('Duplicate document paths; audit refused.')
    for path in paths:
        if len(path.split('/')) % 2 or path.startswith('/') or '..' in path.split('/'):
            raise ValueError('Invalid document path.')
    missing = COLLECTIONS - set(snapshot.get('completeCollections', []))
    candidates = []
    for doc in docs:
        data, path = doc['data'], doc['path']
        markers = {'isSampleData': data.get('isSampleData') is True,
                   'sampleVersion': data.get('sampleVersion') == 'v2',
                   'createdBy': data.get('createdBy') == 'sample_seed'}
        if not any(markers.values()):
            continue
        ident = path.split('/')[-1]
        # Conservative: matching bare IDs may be ambiguous; never erase on that basis.
        inbound = [other['path'] for other in docs if other['path'] != path and
                   any(v == ident or v == path or v.endswith('/documents/' + path)
                       for v in strings(other['data']))]
        blockers = []
        if not all(markers.values()):
            blockers.append('partial-metadata')
        if missing:
            blockers.append('incomplete-reference-inventory')
        if path.split('/')[0] in PROTECTED:
            blockers.append('protected-operational-document-reconciliation-required')
        if inbound:
            blockers.append('referenced-or-ambiguous-id')
        if not doc.get('updateTime'):
            blockers.append('missing-update-precondition')
        candidates.append({'path': path, 'markers': markers, 'updateTime': doc.get('updateTime'),
                           'inboundReferences': inbound, 'blockers': blockers,
                           'approved': path in approved,
                           'reviewCandidate': not blockers})
    unknown_approvals = set(approved) - {c['path'] for c in candidates}
    if unknown_approvals:
        raise ValueError('Allowlist contains documents outside the audited candidates.')
    return {'projectId': project_id, 'mode': 'read-only-dry-run', 'writes': 0,
            'missingCollections': sorted(missing), 'candidates': candidates,
            'countsByCollection': dict(Counter(c['path'].split('/')[0] for c in candidates)),
            'deletionExecuted': False,
            'warning': 'Approval is a review record only. This tool has no delete capability.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--allowlist', type=Path, help='Reviewed JSON list of exact document paths')
    args = parser.parse_args()
    raw = args.snapshot.read_bytes()
    approved = json.loads(args.allowlist.read_text(encoding='utf-8')) if args.allowlist else []
    result = audit(json.loads(raw), args.project, approved)
    result['snapshotSha256'] = hashlib.sha256(raw).hexdigest()
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
