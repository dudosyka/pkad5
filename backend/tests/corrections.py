import json
import os
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
import unittest

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

BASE = os.environ['BASE_URL']
DATABASE_URL = os.environ['DATABASE_URL']
if urlsplit(DATABASE_URL).hostname != 'db' or os.environ.get('ALLOW_TEST_WRITES') != 'isolated-copy':
    raise RuntimeError('Use an isolated database copy at hostname db and ALLOW_TEST_WRITES=isolated-copy.')


def request(path, body=None, headers=None):
    req = Request(BASE + path, data=None if body is None else json.dumps(body).encode(),
                  headers={'Content-Type': 'application/json', **(headers or {})})
    try:
        with urlopen(req, timeout=120) as response:
            return response.status, json.load(response)
    except HTTPError as error:
        return error.code, json.load(error)


def cached_dashboard(etag=None):
    req = Request(BASE + '/api/dashboard', headers={'If-None-Match': etag} if etag else {})
    try:
        with urlopen(req, timeout=30) as response:
            return response.status, response.headers['ETag'], json.load(response)
    except HTTPError as error:
        if error.code != 304:
            raise
        return 304, error.headers['ETag'], None


class Corrections(unittest.TestCase):
    def setUp(self):
        self.db = psycopg.connect(DATABASE_URL, autocommit=True, row_factory=dict_row)
        self.addCleanup(self.db.close)
        row = self.db.execute('SELECT raw_id FROM core.quarantine ORDER BY raw_id LIMIT 1').fetchone()
        self.raw_id = row['raw_id']
        status, detail = request(f'/api/quarantine/{self.raw_id}')
        self.assertEqual(status, 200)
        self.path = f'/api/quarantine/{self.raw_id}/correct'
        self.body = dict(source_record=detail['source_record'], expected_correction_id=detail['expected_correction_id'],
                         order_id='FD-990000001', ordered_at='2026-06-01T12:30:00',
                         customer_id='U001', restaurant_id='R1', dish_id='D1', quantity=2,
                         total_amount='1234.56', fulfillment_type='delivery', courier_id='C012',
                         phone_extension='42', comment='Проверка на отдельной копии базы')

    def state(self):
        return self.db.execute('SELECT core.current_metrics() AS metrics, (SELECT count(*) FROM core.quarantine_corrections) AS corrections, (SELECT count(*) FROM core.pipeline_runs) AS runs').fetchone()

    def test_busy_pipeline(self):
        with psycopg.connect(DATABASE_URL) as locker:
            locker.execute("SELECT pg_advisory_xact_lock(hashtext(current_database()),hashtext('core.run_pipeline'))")
            status, error = request(self.path, self.body)
            self.assertEqual(status, 409, error)

    def test_validation_rollback_commit_and_rerun(self):
        before = self.state()
        _, initial_etag, initial_dashboard = cached_dashboard()
        status, result = request('/api/correction-options')
        self.assertEqual(status, 200)
        self.assertTrue(all(result[key] for key in ('customers', 'couriers', 'restaurants', 'dishes')))
        self.assertEqual(request(self.path, self.body, {'Origin': 'https://unrelated.example'})[0], 403)
        for changes in ({'quantity': 0}, {'quantity': 1.5}, {'total_amount': '-1'}, {'total_amount': '1.001'}, {'customer_id': 'U999'}, {'unexpected': 'ignored?'}, {'ordered_at': '2026-02-31T12:30'}, {'fulfillment_type': 'pickup'}):
            with self.subTest(changes=changes):
                status, error = request(self.path, {**self.body, **changes})
                self.assertEqual(status, 422, error)
        stale = {**self.body['source_record'], 'order_id': 'FD-1'}
        self.assertEqual(request(self.path, {**self.body, 'source_record': stale})[0], 409)
        existing = self.db.execute('SELECT order_id FROM core.orders ORDER BY order_id LIMIT 1').fetchone()['order_id']
        status, error = request(self.path, {**self.body, 'order_id': existing})
        self.assertEqual(status, 422, error)
        self.assertIn('order_id', error['detail']['fields'])
        self.assertEqual(self.state(), before, 'Invalid correction must roll back pipeline, audit, and business changes.')
        self.assertEqual(cached_dashboard(initial_etag)[0], 304, 'Rolled-back edits must keep the cached snapshot valid.')

        status, result = request(self.path, self.body)
        self.assertEqual(status, 200, result)
        self.assertEqual(result['status'], 'loaded')
        self.assertEqual(result['order_id'], self.body['order_id'])
        order = self.db.execute('SELECT * FROM core.orders WHERE order_id=%s', (result['order_id'],)).fetchone()
        self.assertEqual(order['customer_phone_extension'], '42')
        self.assertEqual(order['courier_id'], 'C012')
        self.assertIsNone(self.db.execute('SELECT 1 FROM core.quarantine WHERE raw_id=%s', (order['source_raw_id'],)).fetchone())
        saved = self.state()
        self.assertEqual(saved['corrections'], before['corrections'] + 1)
        self.assertEqual(saved['runs'], before['runs'] + 1)
        self.assertEqual(saved['metrics']['raw_checksum'], before['metrics']['raw_checksum'])
        status, corrected_etag, corrected_dashboard = cached_dashboard(initial_etag)
        self.assertEqual(status, 200, 'A committed correction must invalidate cached analytics.')
        self.assertNotEqual(corrected_etag, initial_etag)
        self.assertEqual(corrected_dashboard['summary']['orders'], saved['metrics']['loaded'])
        self.assertNotEqual(corrected_dashboard['summary'], initial_dashboard['summary'])
        self.assertEqual(request(self.path, self.body)[0], 409)
        self.assertEqual(self.state(), saved)

        self.db.execute('SELECT core.run_pipeline()')
        after_rerun = self.state()
        self.assertEqual(after_rerun['metrics'], saved['metrics'], 'A rerun must preserve the correction.')
        self.assertEqual(cached_dashboard(corrected_etag)[0], 304, 'Identical source data must reuse its statistics after another run.')
        audit = self.db.execute('SELECT * FROM core.quarantine_corrections WHERE correction_id=%s', (result['correction_id'],)).fetchone()
        self.assertEqual(audit['source_record'], self.body['source_record'])
        self.assertEqual(audit['run_id'], result['run_id'])
        self.assertEqual(audit['corrected_record']['order_id'], self.body['order_id'])
        self.assertTrue(request('/api/corrections')[1]['rows'])
        self.assertTrue(all(row['passed'] for row in request('/api/quality')[1]['checks']))
        self.assertEqual(self.db.execute('SELECT count(*) AS n FROM core.raw_records WHERE source_record=%s', (Jsonb(self.body['source_record']),)).fetchone()['n'],
                         self.db.execute('SELECT count(*) AS n FROM public.raw_data_02 r WHERE to_jsonb(r)=%s', (Jsonb(self.body['source_record']),)).fetchone()['n'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
