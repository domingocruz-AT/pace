import datetime as dt
import unittest
from collector import normalize, token_rows, SchemaError, amount, NoRedirect

class UsageTests(unittest.TestCase):
    def setUp(self):
        self.start = dt.date(2026, 10, 10)
        self.end = dt.date(2026, 10, 12)
        self.history = {'series': [{'total': 30}], 'data': [{'date': '2026-10-10', 'values': {'a': 10}}, {'date': '2026-10-12', 'values': {'a': 15, 'b': 5}}], 'data_freshness_ts': '2026-10-12T01:00:00Z'}
        self.estimate = {'estimated_usage_usd_micros': 1_200_000}
    def test_totals_dates_and_microdollars(self):
        result = normalize(self.history, self.estimate, self.start, self.end)
        self.assertEqual(result['credits'], 30)
        self.assertEqual(result['todayCredits'], 20)
        self.assertEqual(result['estimatedUSD'], 1.2)
        self.assertEqual([row['credits'] for row in result['daily']], [10, 0, 20])
    def test_mismatch_fails_closed(self):
        self.history['series'][0]['total'] = 900
        with self.assertRaises(SchemaError): normalize(self.history, self.estimate, self.start, self.end)
    def test_duplicate_dates_rejected(self):
        self.history['data'].append(self.history['data'][0])
        with self.assertRaises(SchemaError): normalize(self.history, self.estimate, self.start, self.end)
    def test_nonfinite_and_invalid_values_rejected(self):
        for value in (float('nan'), float('inf'), -1, True, '30', None):
            with self.assertRaises(SchemaError): amount(value)
    def test_redirects_never_forward_auth(self):
        self.assertIsNone(NoRedirect().redirect_request(None, None, 302, '', {}, 'https://elsewhere.invalid'))
    def test_missing_estimate_is_not_zero(self):
        with self.assertRaises(KeyError): normalize(self.history, {}, self.start, self.end)
    def test_tokens_aggregate_same_model_and_components(self):
        data = {'data': [{'date': '2026-10-12', 'groups': [
            {'dimensions': {'model': 'sol'}, 'uncached_text_input_tokens': 10, 'cached_text_input_tokens': 20, 'text_output_tokens': 3},
            {'dimensions': {'model': 'sol'}, 'text_output_tokens': 7},
            {'is_other': True, 'text_output_tokens': 5}]}]}
        self.assertEqual(token_rows(data, self.start, self.end), {'2026-10-12': {'sol': 40, 'other': 5}})
    def test_tokens_legacy_model_total(self):
        data = {'data': [{'date': '2026-10-12', 'models': [{'model': 'astra', 'text_total_tokens': 99, 'text_output_tokens': 3}]}]}
        self.assertEqual(token_rows(data, self.start, self.end)['2026-10-12']['astra'], 99)
    def test_tokens_reject_invalid_dates_and_values(self):
        for row in [{'date': '2026-11-01', 'models': []}, {'date': '2026-10-12', 'models': [{'model': 'sol', 'text_total_tokens': -1}]}]:
            with self.assertRaises(SchemaError): token_rows({'data': [row]}, self.start, self.end)

if __name__ == '__main__': unittest.main()
