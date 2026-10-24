import json
import unittest
from live_schema_summary import PROJECT, classify, day, summarize


class LiveSchemaSummaryTests(unittest.TestCase):
    def test_provenance_is_not_business_validity(self):
        self.assertEqual(classify({'createdBy': 'sample_seed'}), 'seed-origin')
        self.assertEqual(classify({'createdBy': 'uid', 'isSampleData': True}), 'review-required')
        self.assertEqual(classify({'created_by': 'uid'}), 'non-seed-with-creator')
        self.assertEqual(classify({}), 'unclear-provenance')

    def test_wib_day_is_not_utc_day(self):
        self.assertEqual(day('2026-10-16T18:00:00Z'), '2026-10-17')
        self.assertIsNone(day('2026-10-15'))

    def test_output_never_contains_private_values_or_ids(self):
        docs = [{'path': 'users/private-uid', 'data': {'email': 'private@example.invalid'},
                 'rawFields': {'email': {'stringValue': 'private@example.invalid'}}},
                {'path': 'inventory/seed-private-id', 'data': {'createdBy': 'sample_seed'}},
                {'path': 'inventory_transactions/private-receipt', 'data': {'createdBy': 'private-uid', 'itemId': 'seed-private-id', 'amount': 987654321}}]
        result = summarize({'projectId': PROJECT, 'allCollectionsEnumerated': True,
                            'completeCollections': ['users', 'inventory', 'inventory_transactions'],
                            'capturedAtUtc': '2026-10-16T23:00:00Z', 'documents': docs})
        serialized = json.dumps(result)
        for private in ['private-uid', 'private@example.invalid', 'seed-private-id', 'private-receipt', '987654321']:
            self.assertNotIn(private, serialized)
        self.assertEqual(result['dataIntegrityConflicts'][0]['records'], 1)

    def test_wrong_project_and_partial_inventory_are_refused(self):
        for snapshot in [{'projectId': 'other', 'allCollectionsEnumerated': True},
                         {'projectId': PROJECT, 'allCollectionsEnumerated': False}]:
            with self.assertRaises(ValueError):
                summarize(snapshot)


if __name__ == '__main__':
    unittest.main()
