#!/usr/bin/env python3
"""Exercise generated rule-set transport at startup against a local HTTP server."""
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"version":3,"rules":[]}')

    def log_message(self, *_args):
        pass


binary, generated = sys.argv[1:]
config = json.loads(Path(generated).read_text())
# Isolate the rule downloader from WireGuard connectivity and inbound listeners.
config = {"outbounds": config["outbounds"], "route": {"rule_set": config["route"]["rule_set"]}}
environment = {k: v for k, v in os.environ.items() if not k.startswith("ENABLE_DEPRECATED_")}
with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
    threading.Thread(target=server.serve_forever, daemon=True).start()
    for rule in config["route"]["rule_set"]:
        rule["url"] = f"http://127.0.0.1:{server.server_port}/{rule['tag']}.json"
        rule["format"] = "source"
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "config.json"
        path.write_text(json.dumps(config))
        process = subprocess.Popen([binary, "run", "-c", str(path)], env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            output, _ = process.communicate(timeout=3)
            raise AssertionError(f"sing-box exited during startup ({process.returncode}):\n{output}")
        except subprocess.TimeoutExpired:
            process.terminate()
            output, _ = process.communicate(timeout=5)
            assert "sing-box started" in output, output
            assert "updated rule-set" in output, output
            assert "FATAL" not in output and "deprecated" not in output.lower(), output
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    server.shutdown()
print("PASS: generated rule downloader starts without deprecated-feature overrides")
