"""Offline, read-only, aggregate-only inventory from the private audit snapshot.

Never emits document IDs, text, user identities, money amounts or credentials.
Usage: python tools/live_schema_summary.py --snapshot build/audit_android/production-snapshot.json --output build/audit_android/inventory.json
"""
import argparse
import json
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

PROJECT = 'seicycle-kebun-sei'
WIB = timezone(timedelta(hours=7))
REFERENCES = {'itemId': 'inventory', 'inventoryItemId': 'inventory',
              'batchId': 'batches', 'logbookId': 'logbooks', 'saleId': 'sales',
              'financeTransactionId': 'finance_transactions',
              'inventoryTransactionId': 'inventory_transactions',
              'sourceBatchId': 'batches', 'destinationBatchId': 'batches'}


def day(value):
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if parsed.tzinfo is None:
            return None
        return parsed.astimezone(WIB).date().isoformat()
    except ValueError:
        return None


def classify(data):
    creator = data.get('createdBy', data.get('created_by'))
    if creator == 'sample_seed':
        return 'seed-origin'
    if data.get('isSampleData') is True or data.get('sampleVersion') == 'v2':
        return 'review-required'
    return 'non-seed-with-creator' if creator else 'unclear-provenance'


def summarize(snapshot):
    if snapshot.get('projectId') != PROJECT or not snapshot.get('allCollectionsEnumerated'):
        raise ValueError('A complete snapshot of the explicitly pinned project is required.')
    roots = [d for d in snapshot['documents'] if len(d['path'].split('/')) == 2]
    seed = {d['path'] for d in roots if classify(d['data']) == 'seed-origin'}
    collections = {}
    for name in sorted(set(snapshot['completeCollections']) | {'report_metadata'}):
        docs = [d for d in roots if d['path'].split('/')[0] == name]
        fields = defaultdict(Counter)
        for d in docs:
            for field, typed in d.get('rawFields', {}).items():
                fields[field].update(typed.keys())
        dates = {}
        for label, getter in {
            'documentCreateDayWib': lambda d: d.get('createTime'),
            'documentUpdateDayWib': lambda d: d.get('updateTime'),
            'businessActivityDayWib': lambda d: next((d['data'][k] for k in
                ['activityDate', 'activity_date', 'transactionDate', 'date',
                 'scheduled_at', 'harvestDate', 'flowDate', 'saleDate'] if k in d['data']), None),
        }.items():
            dates[label] = dict(sorted(Counter(day(getter(d)) for d in docs if day(getter(d))).items()))
        collections[name] = {
            'rootDocuments': len(docs),
            'provenance': dict(Counter(classify(d['data']) for d in docs)),
            'createdBySampleSeed': sum(d['data'].get('createdBy') == 'sample_seed' for d in docs),
            'isSampleDataTrue': sum(d['data'].get('isSampleData') is True for d in docs),
            'sampleVersionV2': sum(d['data'].get('sampleVersion') == 'v2' for d in docs),
            'fields': {k: dict(v) for k, v in sorted(fields.items())},
            'missingIsDeleted': sum('isDeleted' not in d['data'] for d in docs),
            **dates,
        }
    conflicts = Counter()
    for d in roots:
        if d['path'] in seed:
            continue
        refs = dict(REFERENCES)
        if d['data'].get('relatedCollection') in collections:
            refs['relatedId'] = d['data']['relatedCollection']
        if d['data'].get('sourceCollection') in collections:
            refs['sourceId'] = d['data']['sourceCollection']
        for key, target in refs.items():
            if target + '/' + str(d['data'].get(key)) in seed:
                conflicts[(d['path'].split('/')[0], key, target)] += 1
    return {
        'projectId': PROJECT, 'databaseId': '(default)',
        'capturedAtUtc': snapshot['capturedAtUtc'],
        'mode': 'read-only-aggregate', 'writes': 0,
        'rootDocuments': len(roots), 'subcollectionDocuments': len(snapshot['documents']) - len(roots),
        'provenance': dict(Counter(classify(d['data']) for d in roots)),
        'collections': collections,
        'dataIntegrityConflicts': [{'collection': c, 'field': f, 'targetCollection': t, 'records': n}
            for (c, f, t), n in sorted(conflicts.items())],
        'limitations': ['Point-in-time reads are not a single database-wide transaction.',
                       'Non-seed provenance does not validate a business transaction.',
                       'Absent documents cannot reveal contents of manually deleted finance records.',
                       'Aggregated reference matches do not prove historical balances.'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = summarize(json.loads(args.snapshot.read_text(encoding='utf-8')))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({k: result[k] for k in ['projectId', 'databaseId', 'rootDocuments', 'subcollectionDocuments', 'provenance', 'dataIntegrityConflicts', 'writes']}))


if __name__ == '__main__':
    main()
