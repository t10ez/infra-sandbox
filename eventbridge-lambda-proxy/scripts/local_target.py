"""Stand-in target for floci runs. Logs each request as JSON on stdout.

Usage: python3 local_target.py [--fail-b]
--fail-b answers 503 on /reports/b to exercise the retry path.
"""
import datetime
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

FAIL_B = "--fail-b" in sys.argv


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        print(json.dumps({
            "received_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "path": self.path,
            "idempotency_key": self.headers.get("X-Idempotency-Key"),
            "report_type": self.headers.get("X-Report-Type"),
            "body": json.loads(body or b"{}"),
        }), flush=True)
        status = 503 if FAIL_B and self.path.endswith("/b") else 200
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, *args):
        pass


HTTPServer(("0.0.0.0", 9000), Handler).serve_forever()
