import copy
import unittest
from sample_data_audit import audit, COLLECTIONS


class SampleAuditTest(unittest.TestCase):
    def setUp(self):
        self.snapshot = {'projectId': 'demo-offline', 'completeCollections': sorted(COLLECTIONS),
                         'documents': [{'path': 'schedules/candidate', 'updateTime': 'reviewed-time',
                                        'data': {'isSampleData': True, 'sampleVersion': 'v2',
                                                 'createdBy': 'sample_seed'}}]}

    def test_dry_run_does_not_mutate_snapshot(self):
        original = copy.deepcopy(self.snapshot)
        result = audit(self.snapshot, 'demo-offline')
        self.assertEqual(self.snapshot, original)
        self.assertEqual(result['writes'], 0)
        self.assertFalse(result['deletionExecuted'])
        self.assertTrue(result['candidates'][0]['reviewCandidate'])

    def test_partial_marker_is_blocked(self):
        del self.snapshot['documents'][0]['data']['sampleVersion']
        self.assertIn('partial-metadata', audit(self.snapshot, 'demo-offline')['candidates'][0]['blockers'])

    def test_real_reference_blocks(self):
        self.snapshot['documents'].append({'path': 'logbooks/real', 'data': {'scheduleId': 'candidate'}})
        self.assertTrue(audit(self.snapshot, 'demo-offline')['candidates'][0]['inboundReferences'])

    def test_canonical_and_ledger_are_protected_even_approved(self):
        for path in ['farm_modules/lele', 'inventory/item', 'inventory_transactions/ledger', 'users/actual']:
            self.snapshot['documents'][0]['path'] = path
            row = audit(self.snapshot, 'demo-offline', [path])['candidates'][0]
            self.assertFalse(row['reviewCandidate'])
            self.assertTrue(row['approved'])

    def test_project_mismatch_fails(self):
        with self.assertRaises(ValueError):
            audit(self.snapshot, 'seicycle-kebun-sei')

    def test_prefix_without_markers_is_not_candidate(self):
        self.snapshot['documents'].append({'path': 'schedules/sample_real', 'data': {}})
        self.assertEqual(len(audit(self.snapshot, 'demo-offline')['candidates']), 1)

    def test_incomplete_inventory_and_unknown_approval_fail_closed(self):
        self.snapshot['completeCollections'] = []
        self.assertFalse(audit(self.snapshot, 'demo-offline')['candidates'][0]['reviewCandidate'])
        with self.assertRaises(ValueError):
            audit(self.snapshot, 'demo-offline', ['users/missing'])


if __name__ == '__main__':
    unittest.main()
