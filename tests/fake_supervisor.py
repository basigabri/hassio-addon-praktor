"""A stand-in for the Home Assistant Supervisor API, for the App smoke test.

It serves the App's options the way bashio reads them
(GET /addons/self/options/config with the SUPERVISOR_TOKEN as a bearer
token) and logs every request, so the test can see what the App asked for.

Usage: fake_supervisor.py OPTIONS_JSON_FILE TOKEN
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OPTIONS_FILE, TOKEN = sys.argv[1], sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            self._send(401, {"result": "error", "message": "unauthorized"})
            return
        if self.command == "GET" and self.path == "/addons/self/options/config":
            with open(OPTIONS_FILE, encoding="utf-8") as f:
                self._send(200, {"result": "ok", "data": json.load(f)})
            return
        self._send(404, {"result": "error", "message": f"not faked: {self.path}"})

    do_GET = _handle
    do_POST = _handle

    def log_message(self, format, *args):  # noqa: A002 (BaseHTTPRequestHandler API)
        sys.stderr.write("supervisor: %s\n" % (format % args))
        sys.stderr.flush()


ThreadingHTTPServer(("0.0.0.0", 80), Handler).serve_forever()
