#!/usr/bin/env python3
"""calarch web dashboard — HTTP server (localhost:8765)"""
import http.server, subprocess, json, os, sys

DIR = os.path.join(os.path.dirname(__file__), '..', 'web')
CORE = os.path.join(os.path.dirname(__file__), 'core.sh')

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/status':
            data = subprocess.check_output(['bash', CORE, 'api'], text=True, timeout=2)
            self.send_json(json.loads(data))
        elif self.path == '/api/config':
            data = subprocess.check_output(['bash', CORE, 'list-json'], text=True, timeout=2)
            self.send_json(json.loads(data))
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/set/'):
            key = self.path.split('/')[-2]
            val = self.path.split('/')[-1]
            try:
                subprocess.check_output(['bash', CORE, 'set', key, val], text=True, timeout=5)
                self.send_json({"ok": True, "key": key, "val": val})
            except subprocess.CalledProcessError as e:
                self.send_json({"ok": False, "error": e.output})
        elif self.path == '/api/grace':
            subprocess.check_output(['bash', CORE, 'grace_confirm', 'all'], text=True, timeout=2)
            self.send_json({"ok": True})

    def send_json(self, obj):
        b = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a): pass

if __name__ == '__main__':
    os.chdir(DIR)
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    http.server.HTTPServer(('0.0.0.0', port), Handler).serve_forever()
