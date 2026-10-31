from contextlib import closing
import base64
import http.client
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import patch
import server

PROFILE = base64.b64encode(json.dumps(dict(sex='M', age=35, height_m=1.75,
                                          weight_kg=75, ring_size=10)).encode()).decode()

class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.cli = Path(self.temp.name)/'oura.exe'
        self.cli.touch()
        self.service = server.Server(('127.0.0.1', 0), 'secret-code', self.cli, Path(self.temp.name))
        self.thread = threading.Thread(target=self.service.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.service.shutdown()
        self.service.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, method='POST', body=b'x', **headers):
        defaults = {'Authorization': 'Bearer secret-code', 'Content-Type': 'application/vnd.sqlite3',
                    'X-OpenHealth-Profile': PROFILE}
        defaults.update(headers)
        conn = http.client.HTTPConnection(*self.service.server_address, timeout=3)
        conn.request(method, '/v1/health' if method == 'GET' else '/v1/analyze?tz=3', body, defaults)
        response = conn.getresponse()
        code, data = response.status, json.loads(response.read())
        conn.close()
        return code, data

    def test_authentication_precedes_upload(self):
        with patch.object(server, 'analyze') as run:
            self.assertEqual(self.request(Authorization='bad')[0], 401)
            run.assert_not_called()

    def test_authenticated_health(self):
        self.assertEqual(self.request('GET')[1]['engine_available'], True)

    def test_invalid_database_is_rejected(self):
        self.assertEqual(self.request()[0], 422)

    def test_bad_profile_is_rejected_before_analysis(self):
        self.assertEqual(self.request(**{'X-OpenHealth-Profile': 'invalid'})[0], 400)
        bad = base64.b64encode(b'{"sex":"M","age":NaN}').decode()
        self.assertEqual(self.request(**{'X-OpenHealth-Profile': bad})[0], 400)

    def test_parallel_analysis_returns_busy(self):
        self.service.gate.acquire()
        try:
            self.assertEqual(self.request()[0], 409)
        finally:
            self.service.gate.release()

    def test_success_and_failure_delete_uploaded_data(self):
        paths = []
        def run(db, *_):
            paths.append(db.parent)
            self.assertTrue(db.exists())
            self.assertEqual(json.loads((db.parent/'profile.json').read_text())['age'], 35)
            return {'summary': {'nights': []}}
        with patch.object(server, 'analyze', side_effect=run):
            self.assertEqual(self.request(body=b'example snapshot')[0], 200)
        self.assertFalse(paths[0].exists())
        def fail(db, *_):
            paths.append(db.parent)
            raise ValueError('bad data')
        with patch.object(server, 'analyze', side_effect=fail):
            self.assertEqual(self.request()[0], 422)
        self.assertFalse(paths[-1].exists())

    def test_engine_command_is_offline_and_shell_free(self):
        db = Path(self.temp.name)/'ring.db'
        with closing(sqlite3.connect(db)) as conn:
            conn.execute('CREATE TABLE events (id INTEGER)')
        def execute(args, **kwargs):
            self.assertEqual(args[1:], ['--db', str(db), 'analyze', '--tz-offset', '3'])
            self.assertNotIn('shell', kwargs)
            kwargs['stdout'].write(b'{"nights":[]}')
            class Result:
                returncode = 0
            return Result()
        with patch.object(server.subprocess, 'run', side_effect=execute):
            result = server.analyze(db, self.cli, Path(self.temp.name), 3)
        self.assertEqual(result['summary']['nights'], [])
        self.assertEqual(result['service_version'], 1)

if __name__ == '__main__':
    unittest.main()
