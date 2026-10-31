"""Private PC analysis gateway. Bind only to loopback; use Tailscale Serve for HTTPS."""
import argparse
import base64
import hmac
import json
import math
import os
from pathlib import Path
import secrets
import sqlite3
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

MAX_UPLOAD = 256 * 1024 * 1024
MAX_RESULT = 32 * 1024 * 1024


def profile_from_header(value):
    if not value or len(value) > 4096:
        raise ValueError('A saved profile is required. Save your profile in the app first.')
    profile = json.loads(base64.b64decode(value, validate=True))
    result = {}
    if not isinstance(profile, dict) or profile.get('sex') not in ('M', 'F', 'O'):
        raise ValueError('Invalid profile')
    result['sex'] = profile['sex']
    for field, low, high in [('age', 1, 120), ('height_m', .4, 2.6),
                             ('weight_kg', 3, 500), ('ring_size', 1, 20)]:
        value = profile.get(field)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError('Invalid profile: ' + field)
        result[field] = value
    return result


def analyze(db, cli, root, tz):
    # Check the uploaded snapshot without creating a database or accepting SQL.
    with db.open('rb') as source:
        if source.read(16) != b'SQLite format 3\x00':
            raise ValueError('Upload is not a SQLite ring export')
    conn = sqlite3.connect(db.as_uri() + '?mode=ro', uri=True)
    try:
        conn.execute('PRAGMA trusted_schema=OFF')
        # Bound malformed databases' integrity-check work.
        import time
        deadline = time.monotonic() + 10
        conn.set_progress_handler(lambda: int(time.monotonic() > deadline), 10000)
        if conn.execute('PRAGMA quick_check(1)').fetchone()[0] != 'ok':
            raise ValueError('Database integrity check failed')
    finally:
        conn.close()
    output = db.parent / 'report.json'
    with output.open('wb') as stream:
        proc = subprocess.run([str(cli), '--db', str(db), 'analyze', '--tz-offset', str(tz)],
                              cwd=root, stdout=stream, stderr=subprocess.DEVNULL, timeout=300,
                              check=False, env={k: v for k, v in os.environ.items()
                                               if k not in ('OURA_KEY_FILE', 'OURA_DB_FILE')})
    if proc.returncode or output.stat().st_size > MAX_RESULT:
        raise ValueError('Analysis failed. Check the exported database and desktop engine.')
    summary = json.loads(output.read_text(encoding='utf-8'))
    if not isinstance(summary, dict) or summary.get('error'):
        raise ValueError('The engine could not analyze this database')
    from datetime import datetime, timezone
    return {'service_version': 1, 'generated_at': datetime.now(timezone.utc).isoformat(),
            'notes': ['Sleep stages with source signals are estimates, not clinical scoring.',
                      'Private ML weights are not included. Model-dependent fields may be unavailable.',
                      'Demographic estimates depend on the profile you saved in the app.'],
            'summary': summary}


class Server(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, token, cli, root):
        self.token, self.cli, self.root = token, cli, root
        self.gate = threading.Lock()
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'
    def log_message(self, *_):
        pass  # No health information, request paths or credentials in access logs.

    def setup(self):
        super().setup()
        self.connection.settimeout(60)

    def reply(self, code, body):
        payload = json.dumps(body, allow_nan=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(payload)

    def authorized(self):
        expected = 'Bearer ' + self.server.token
        if not hmac.compare_digest(self.headers.get('Authorization', '').encode(), expected.encode()):
            self.reply(401, {'error': 'Wrong PC connection code'})
            return False
        return True

    def do_GET(self):
        if not self.authorized():
            return
        if self.path != '/v1/health':
            return self.reply(404, {'error': 'Not found'})
        self.reply(200, {'service_version': 1, 'ready': True,
                         'engine_available': self.server.cli.is_file()})

    def do_POST(self):
        if not self.authorized():
            return
        url = urlsplit(self.path)
        if url.path != '/v1/analyze':
            return self.reply(404, {'error': 'Not found'})
        if self.headers.get('Transfer-Encoding'):
            return self.reply(400, {'error': 'Content-Length required'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if length <= 0 or length > MAX_UPLOAD:
                return self.reply(413, {'error': 'Database must be between 1 byte and 256 MB'})
            if self.headers.get('Content-Type') != 'application/vnd.sqlite3':
                return self.reply(415, {'error': 'Expected a SQLite snapshot'})
            tz = float(parse_qs(url.query).get('tz', ['0'])[0])
            if not math.isfinite(tz) or abs(tz) > 24:
                raise ValueError('Invalid UTC offset')
            profile = profile_from_header(self.headers.get('X-OpenHealth-Profile'))
        except (ValueError, TypeError):
            return self.reply(400, {'error': 'Invalid size, UTC offset or saved profile'})
        if not self.server.gate.acquire(blocking=False):
            return self.reply(409, {'error': 'PC is analyzing another request. Try again shortly.'})
        try:
            # Temporary snapshot and report are deleted even if analysis fails.
            with tempfile.TemporaryDirectory(prefix='openhealth-') as temp:
                db = Path(temp) / 'ring.db'
                with db.open('wb') as destination:
                    remaining = length
                    while remaining:
                        chunk = self.rfile.read(min(1024 * 1024, remaining))
                        if not chunk:
                            raise ValueError('Incomplete upload')
                        destination.write(chunk)
                        remaining -= len(chunk)
                (db.parent / 'profile.json').write_text(json.dumps(profile), encoding='utf-8')
                result = analyze(db, self.server.cli, self.server.root, tz)
            self.reply(200, result)
        except subprocess.TimeoutExpired:
            self.reply(504, {'error': 'PC analysis exceeded five minutes'})
        except (ValueError, sqlite3.Error):
            self.reply(422, {'error': 'Could not analyze the ring snapshot. Check data and engine.'})
        except OSError:
            self.reply(503, {'error': 'PC engine or storage unavailable'})
        finally:
            self.server.gate.release()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--cli', type=Path, default=Path(__file__).with_name('oura.exe'))
    args = parser.parse_args()
    cli = args.cli.resolve()
    if not cli.is_file():
        parser.error('oura.exe is missing; extract the complete Windows service package')
    token = secrets.token_urlsafe(32)
    print('Open Health PC service. Keep this window open.', flush=True)
    print('Private connection code (changes on restart): ' + token, flush=True)
    print('In an Administrator terminal run: tailscale serve --bg http://127.0.0.1:' + str(args.port), flush=True)
    print('Use the HTTPS .ts.net URL printed by Tailscale in the iPhone app.', flush=True)
    with Server(('127.0.0.1', args.port), token, cli, Path(__file__).resolve().parent) as server:
        server.serve_forever()


if __name__ == '__main__':
    main()
